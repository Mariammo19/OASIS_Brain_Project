# =====================================================================
# Brain volume and dementia in the OASIS Longitudinal MRI dataset
#
# Questions
#   1. At first visit, does normalized whole-brain volume (nWBV) differ
#      between demented and non-demented older adults, after adjusting
#      for age, sex and education?
#   2. Does brain volume change at a different rate in people who
#      develop dementia (the "Converted" group)?
#
# Data: oasis_longitudinal.csv (Kaggle: "MRI and Alzheimers", jboysen)
# Put the file in data/ next to this script and run from the project
# folder. Figures are saved to figures/.
# =====================================================================

library(tidyverse)
library(broom)

dir.create("figures", showWarnings = FALSE)

# ---- Shared style -----------------------------------------------------
pal <- c("Nondemented" = "#2563EB", "Converted" = "#7C3AED", "Demented" = "#F97316")

theme_oasis <- function() {
  theme_minimal(base_size = 14) +
    theme(legend.position = "none",
          plot.title = element_text(face = "bold", colour = "#0F172A"),
          plot.caption = element_text(colour = "#64748B", size = 9),
          panel.grid.minor = element_blank(),
          panel.grid.major.x = element_blank())
}

# ---- 1. Load and rename ----------------------------------------------
raw <- read_csv("data/oasis_longitudinal.csv")

df <- raw |>
  rename(subject_id = `Subject ID`, group = Group, visit = Visit,
         mr_delay = `MR Delay`, sex = `M/F`, age = Age, educ = EDUC,
         ses = SES, mmse = MMSE, cdr = CDR, etiv = eTIV, nwbv = nWBV)

# ---- 2. Explore -------------------------------------------------------
glimpse(df)
colSums(is.na(df))          # ses: 19 missing, mmse: 2 missing
count(df, group)            # scans: Converted 37, Demented 146, Nondemented 190
n_distinct(df$subject_id)   # 150 people

# ---- 3. Baseline table: one row per person ---------------------------
# Each person has 2-5 scans, so group comparisons use the first visit only.
# "Converted" people (non-demented at first, demented later) are left out
# of the baseline comparison and used in section 7.
base <- df |>
  filter(visit == 1) |>
  filter(group %in% c("Nondemented", "Demented")) |>
  mutate(group = factor(group, levels = c("Nondemented", "Demented")),
         sex = factor(sex))

count(base, group)          # 72 Nondemented, 64 Demented

# ---- 4. Descriptive table --------------------------------------------
base |>
  group_by(group) |>
  summarise(n = n(),
            age_mean = mean(age), age_sd = sd(age),
            nwbv_mean = mean(nwbv), nwbv_sd = sd(nwbv),
            mmse_median = median(mmse, na.rm = TRUE),
            educ_mean = mean(educ))

# ---- 5. Plots ---------------------------------------------------------
# 5a. Brain volume by group
ggplot(base, aes(group, nwbv, fill = group, colour = group)) +
  geom_boxplot(alpha = 0.25, width = 0.45, outlier.shape = NA, linewidth = 0.8) +
  geom_jitter(width = 0.1, alpha = 0.6, size = 1.8) +
  scale_fill_manual(values = pal) +
  scale_colour_manual(values = pal) +
  scale_x_discrete(labels = c("Nondemented" = "Non-demented")) +
  labs(title = "Brain volume at first visit",
       x = NULL, y = "nWBV",
       caption = "nWBV = normalized whole-brain volume. OASIS longitudinal dataset. Each dot is one person.") +
  theme_oasis()
ggsave("figures/nwbv_by_group.png", width = 7, height = 5.5, dpi = 300)

# 5b. Brain volume vs age
ggplot(base, aes(age, nwbv, colour = group, fill = group)) +
  geom_point(alpha = 0.6, size = 1.8) +
  geom_smooth(method = "lm", se = TRUE, alpha = 0.15, linewidth = 1) +
  scale_colour_manual(values = pal, labels = c("Nondemented" = "Non-demented")) +
  scale_fill_manual(values = pal, labels = c("Nondemented" = "Non-demented")) +
  labs(title = "Brain volume by age",
       x = "Age (years)", y = "nWBV", colour = NULL, fill = NULL,
       caption = "nWBV = normalized whole-brain volume. Lines are linear fits with 95% confidence bands.") +
  theme_oasis() +
  theme(legend.position = "top")
ggsave("figures/nwbv_vs_age.png", width = 7, height = 5.5, dpi = 300)

# 5c. MMSE by group (descriptive only)
ggplot(base, aes(group, mmse, fill = group, colour = group)) +
  geom_boxplot(alpha = 0.25, width = 0.45, outlier.shape = NA, linewidth = 0.8) +
  geom_jitter(width = 0.1, height = 0.15, alpha = 0.6, size = 1.8) +
  scale_fill_manual(values = pal) +
  scale_colour_manual(values = pal) +
  scale_x_discrete(labels = c("Nondemented" = "Non-demented")) +
  labs(title = "MMSE score at first visit",
       x = NULL, y = "MMSE (0-30)",
       caption = "MMSE = Mini-Mental State Examination. Each dot is one person.") +
  theme_oasis()
ggsave("figures/mmse_by_group.png", width = 7, height = 5.5, dpi = 300)

# ---- 6. Group comparisons and regression ------------------------------
# Wilcoxon rank-sum test per variable, Benjamini-Hochberg correction.
# MMSE differences are expected by construction (dementia status is partly
# defined by cognitive testing), so MMSE is described, not used as a predictor.
tests <- base |>
  select(group, age, educ, etiv, nwbv, mmse) |>
  pivot_longer(-group, names_to = "variable", values_to = "value") |>
  group_by(variable) |>
  summarise(p = wilcox.test(value ~ group)$p.value, .groups = "drop") |>
  mutate(p_adj = p.adjust(p, method = "BH")) |>
  arrange(p_adj)
tests

# Sex distribution by group
chisq.test(table(base$group, base$sex))

# Logistic regression. nWBV is standardized, so its odds ratio is per 1 SD.
base <- base |> mutate(nwbv_z = as.numeric(scale(nwbv)))

fit <- glm(group ~ nwbv_z + age + sex + educ, data = base, family = binomial)
tidy(fit, exponentiate = TRUE, conf.int = TRUE)

# ---- 7. Longitudinal: yearly change in brain volume -------------------
# For each person with 2+ scans, fit a line through nWBV over time and keep
# the slope (change per year). Then compare slopes between groups.
slopes <- df |>
  filter(!is.na(nwbv)) |>
  mutate(years = mr_delay / 365.25) |>
  group_by(subject_id, group) |>
  filter(n() >= 2) |>
  summarise(slope = coef(lm(nwbv ~ years))[2], .groups = "drop")

slopes |>
  group_by(group) |>
  summarise(n = n(), median_slope = median(slope), mean_slope = mean(slope))

kruskal.test(slope ~ group, data = slopes)
pairwise.wilcox.test(slopes$slope, slopes$group, p.adjust.method = "BH")

slopes |>
  mutate(group = factor(group, levels = c("Nondemented", "Converted", "Demented"))) |>
  ggplot(aes(group, slope, fill = group, colour = group)) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "#64748B") +
  geom_boxplot(alpha = 0.25, width = 0.45, outlier.shape = NA, linewidth = 0.8) +
  geom_jitter(width = 0.1, alpha = 0.6, size = 1.8) +
  scale_fill_manual(values = pal) +
  scale_colour_manual(values = pal) +
  scale_x_discrete(labels = c("Nondemented" = "Non-demented")) +
  labs(title = "Change in brain volume per year",
       x = NULL, y = "nWBV change per year",
       caption = "Slope of nWBV over repeated scans, one value per person. Dashed line = no change.") +
  theme_oasis()
ggsave("figures/nwbv_slope_by_group.png", width = 7, height = 5.5, dpi = 300)

# ---- 8. Reproducibility ----------------------------------------------
sessionInfo()
