#' @noRd
vary_x <- function(x, yes, ...) {
  if (yes) {
    unsampled_diff <- make_fractionation_mat(x, ...)
    out <- x + unsampled_diff
    out[, "Unsampled"] <- rowSums(unsampled_diff)
    out <- t(apply(out, 1, function(x) {
      x <- linear_rescale(x, c(0, 1))
      abs(x) / sum(abs(x))
    }))
    out[, -which(colnames(out) == "Unsampled")]
  } else {
    x
  }
}

#' @importFrom stats runif
#' @noRd
make_fractionation_mat <- function(x, delta = -0.05) {
  delta <- abs(delta)
  matrix(runif(nrow(x) * ncol(x), -1 * delta, delta), nrow(x), ncol(x))
}

#' @noRd
#' @importFrom dplyr group_by count ungroup mutate bind_rows
#' @importFrom gtools rdirichlet
#' @importFrom tibble as_tibble
#' @importFrom rlang .env .data
produce_mix_props <- function(data, sources, seed_1, seed_2,
                              make_unsampled = TRUE, ...) {
  group_n <- data |>
    group_by(.data$group) |>
    count() |>
    ungroup()
  n_groups <- nrow(group_n)
  alphas <- c(1, 1.5, 2, 2.5, 0.5, 2.5) # each value represents a source
  if (length(sources) != length(alphas)) {
    stop("Number of Dirichlet concentration parameters not the same as number",
         " of sources.")
  }
  set.seed(seed_1)
  x <- rdirichlet(n = n_groups, alpha = alphas) |>
    round(3) |>
    fix_sum_to_one()
  set.seed(seed_2)
  out <- list()
  for (i in seq_len(nrow(group_n))) {
    out[[i]] <- rdirichlet(n = group_n$n[i], alpha = x[i, ] * 10) |>
      round(3) |>
      fix_sum_to_one() |>
      data.frame() |>
      as_tibble() |>
      mutate(group = .env$group_n$group[i])
  }
  out <- bind_rows(out)
  names(out)[seq_along(alphas)] <- sources
  if (make_unsampled) {
    out[, sources] <- vary_x(out[, sources], yes = TRUE, ...)
  }
  out[, order(names(out))] # ensure alphabetical order of names
}

#' @importFrom dplyr bind_rows bind_cols mutate case_match arrange case_match
#' @importFrom purrr map
#' @importFrom rlang .data
#' @noRd
make_mixture_data <- function(si_df, fa_df, stream_1_props, stream_2_props,
                              truth_stream = 1, template_df, ...) {
  if (truth_stream == 1) {
    mixing_props_df <- as.matrix(stream_1_props)
  } else if (truth_stream == 2) {
    mixing_props_df <- as.matrix(stream_2_props)
  } else {
    stop("truth_stream can only have value 1 or 2.")
  }
  out <- bind_rows(
    reshape_isotope_df(si_df), reshape_fattyacids_df(fa_df)
  ) |>
    mutate(
      a = case_match(.data$tracer, "d(13C/12C)" ~ -Inf, .default = 0), b = Inf
    ) |>
    calc_tracer_estimate(...) |>
    arrange(.data$source, .data$tracer_family, .data$tracer) |> # ensure alphabetical order
    split(f = ~ tracer_family + tracer, drop = TRUE) |>
    map(function(tracer_df, props_df) {
      (t(props_df[, tracer_df$source]) * tracer_df$estimate) |>
        colSums() |>
        data.frame(check.names = FALSE) |>
        assign_new_names(unique(tracer_df$tracer))
    }, props_df = mixing_props_df)
  # check if bind_cols is working as intended
  df_stream_1 <- cbind(template_df, bind_cols(out))
  df_stream_2 <- cbind(template_df, stream_2_props)
  stream_1_props <- cbind(template_df, stream_1_props)
  list(df_stream_1 = df_stream_1, df_stream_2 = df_stream_2,
       stream_1_props = stream_1_props)
}

#' @importFrom dplyr group_by summarise ungroup
#' @importFrom rlang .data
#' @noRd
calc_tracer_estimate <- function(x, rand_gen = FALSE, sd_ = NULL, seed = 10) {
  if (rand_gen) {
    set.seed(seed)
    x$sd <- if (!is.null(sd_)) sd_ else x$sd
    group_by(x, .data$source, .data$tracer_family, .data$tracer) |>
      summarise(
        estimate = trun_na_zr(a = .data$a, b = .data$b, mean = .data$mean,
                              sd = .data$sd)
      ) |>
      ungroup()
  } else {
    group_by(x, .data$source, .data$tracer_family, .data$tracer) |>
      summarise(estimate = .data$mean) |>
      ungroup()
  }
}

#' @importFrom dplyr left_join select mutate across
#' @importFrom tidyr pivot_wider
#' @importFrom tidyselect where
#' @importFrom rlang .data
#' @noRd
wrangle_tracer_pars <- function(raw_data_si, raw_data_fa) {
  mu_tab <- left_join(
    reshape_isotope_df(raw_data_si) |>
      select(!c(.data$Study, .data$sd, .data$n, .data$tracer_family)) |>
      pivot_wider(names_from = "tracer", values_from = "mean"),
    reshape_fattyacids_df(raw_data_fa) |>
      select(!c(.data$Study, .data$sd, .data$n, .data$tracer_family)) |>
      pivot_wider(names_from = "tracer", values_from = "mean"),
    by = "source"
  )
  sig_tab <- left_join(
    reshape_isotope_df(raw_data_si) |>
      select(!c(.data$Study, .data$mean, .data$n, .data$tracer_family)) |>
      pivot_wider(names_from = "tracer", values_from = "sd"),
    reshape_fattyacids_df(raw_data_fa) |>
      select(!c(.data$Study, .data$mean, .data$n, .data$tracer_family)) |>
      pivot_wider(names_from = "tracer", values_from = "sd"),
    by = "source"
  )
  n_tab <- left_join(
    reshape_isotope_df(raw_data_si) |>
      select(!c(.data$Study, .data$mean, .data$sd, .data$tracer_family)) |>
      pivot_wider(names_from = "tracer", values_from = "n"),
    reshape_fattyacids_df(raw_data_fa) |>
      select(!c(.data$Study, .data$mean, .data$sd, .data$tracer_family)) |>
      pivot_wider(names_from = "tracer", values_from = "n"),
    by = "source"
  )
  list(mus = mu_tab, sigmas = sig_tab, ns = n_tab)
}

#' @importFrom dplyr select left_join mutate case_match
#' @importFrom tidyr pivot_longer
#' @importFrom tidyselect starts_with ends_with
#' @importFrom rlang .data
#' @noRd
reshape_isotope_df <- function(x) {
  x |>
    select(-ends_with("(SD)"), -ends_with("(n)")) |>
    pivot_longer(
      cols = starts_with("d("), values_to = "mean", names_to = "tracer"
    ) |>
    left_join(
      x |>
        select(.data$source, ends_with("(SD)"), .data$Study) |>
        pivot_longer(
          cols = ends_with("(SD)"), values_to = "sd", names_to = "tracer"
        ) |>
        mutate(tracer = gsub(" (SD)", "", .data$tracer, fixed = TRUE)),
      by = c("source", "Study", "tracer")
    ) |>
    left_join(
      x |>
        select(.data$source, ends_with("(n)"), .data$Study) |>
        pivot_longer(
          cols = ends_with("(n)"), values_to = "n", names_to = "tracer"
        ) |>
        mutate(tracer = gsub(" (n)", "", .data$tracer, fixed = TRUE)),
      by = c("source", "Study", "tracer")
    ) |>
    mutate(tracer_family = "si")
}

#' @importFrom dplyr select left_join mutate
#' @importFrom tidyr pivot_longer
#' @importFrom tidyselect ends_with
#' @importFrom rlang .data
#' @noRd
reshape_fattyacids_df <- function(x) {
  x |>
    select(-.data$Taxa, -ends_with("(SD)"), -ends_with("(n)")) |>
    pivot_longer(
      cols = .data$`24:0`:.data$`20:5w3`, values_to = "mean",
      names_to = "tracer"
    ) |>
    left_join(
      x |>
        select(.data$source, ends_with("(SD)"), .data$Study) |>
        pivot_longer(
          cols = ends_with("(SD)"), values_to = "sd", names_to = "tracer"
        ) |>
        mutate(tracer = gsub(" (SD)", "", .data$tracer, fixed = TRUE)),
      by = c("source", "Study", "tracer")
    ) |>
    left_join(
      x |>
        select(.data$source, ends_with("(n)"), .data$Study) |>
        pivot_longer(
          cols = ends_with("(n)"), values_to = "n", names_to = "tracer"
        ) |>
        mutate(tracer = gsub(" (n)", "", .data$tracer, fixed = TRUE)),
      by = c("source", "Study", "tracer")
    ) |>
    mutate(tracer_family = "fa")
}

#' Compare Mixing Proportions Between Data Streams
#'
#' This function generates a plot to compare the mixing proportions between two data streams 
#' (e.g., chemical tracers and eDNA) for synthetic datasets with agreement and disagreement.
#'
#' @param synth_list_d A list representing the synthetic dataset with divergent mixing proportions.
#' @param synth_list_c A list representing the synthetic dataset with convergent mixing proportions.
#' @param mu_tab A data frame containing the mean tracer
#' signatures for each source. The first column should be named `source`, and
#' the remaining columns should contain numeric tracer values.
#'
#' @return A \code{\link[ggplot2]{ggplot}} object visualizing the comparison of mixing proportions between the two data streams.
#'
#' @details
#' The function compares the mixing proportions from two data streams (`stream_1_props` and `df_stream_2`) 
#' for both divergent and convergent synthetic datasets. It reshapes and aligns the data based on the 
#' reference order provided in `mu_tab`, and then creates a scatter plot with points representing 
#' the proportions from each data stream. The plot includes facets for each source and highlights 
#' agreement or disagreement between the datasets.
#'
#' @importFrom dplyr left_join mutate n
#' @importFrom tidyr pivot_longer
#' @importFrom ggplot2 ggplot geom_point aes geom_abline scale_fill_manual
#' @importFrom ggplot2 scale_shape_manual labs xlim ylim facet_wrap theme_bw
#' @importFrom ggplot2 theme element_text guides guide_legend
#' @importFrom rlang .data
#'
#' @examples
#' library(MixMustR)
#' compare_mixing_proportions(
#'   synth_list_d = synthetic_df_divergent,
#'   synth_list_c = synthetic_df_convergent,
#'   mu_tab = tracer_parameters$mus
#' )
#'
#' @seealso
#' \code{\link{synthetic_df_divergent}}, \code{\link{synthetic_df_convergent}}
#'
#' @export
compare_mixing_proportions <- function(synth_list_d, synth_list_c, mu_tab) {
  rbind(
    left_join(
      reshape_ref_data(
        synth_list_d, target = "stream_1_props", order_ref = mu_tab$source
      ) |>
        data.frame(check.names = FALSE) |>
        mutate(N = seq_len(n())) |>
        pivot_longer(!.data$N, names_to = "source", values_to = "Tracers"),
      reshape_ref_data(
        synth_list_d, target = "df_stream_2", order_ref = mu_tab$source
      ) |>
        data.frame(check.names = FALSE) |>
        mutate(N = seq_len(n())) |>
        pivot_longer(!.data$N, names_to = "source", values_to = "eDNA"),
      by = c("N", "source")
    ) |>
      mutate(`dataset` = "Disagreement (Dataset 2)"),
    left_join(
      reshape_ref_data(
        synth_list_c, target = "stream_1_props", order_ref = mu_tab$source
      ) |>
        data.frame(check.names = FALSE) |>
        mutate(N = seq_len(n())) |>
        pivot_longer(!.data$N, names_to = "source", values_to = "Tracers"),
      reshape_ref_data(
        synth_list_c, target = "df_stream_2", order_ref = mu_tab$source
      ) |>
        data.frame(check.names = FALSE) |>
        mutate(N = seq_len(n())) |>
        pivot_longer(!.data$N, names_to = "source", values_to = "eDNA"),
      by = c("N", "source")
    ) |>
      mutate(`dataset` = "Agreement (Dataset 1)")
  ) |>
    ggplot(data = _) +
      geom_point(
        mapping = aes(x = .data$Tracers, y = .data$eDNA, fill = .data$dataset,
                      shape = .data$dataset), size = 2, alpha = 0.5
      ) +
      geom_abline(slope = 1, linetype = 2) +
      scale_fill_manual(values = c("dodgerblue3", "tomato3")) +
      scale_shape_manual(values = 21:22) +
      labs(x = "From chemical tracers (data stream 1)",
           y = "From eDNA (data stream 2)",
           title = "Simulated mixing proportions",
           fill = "Matrices in:", shape = "Matrices in:") +
      xlim(c(0, 1)) +
      ylim(c(0, 1)) +
      facet_wrap(~ .data$source) +
      theme_bw() +
      theme(
        axis.title = element_text(size = 14),
        axis.text = element_text(size = 10),
        legend.title = element_text(size = 14),
        legend.text = element_text(size = 12),
        legend.position = "inside",
        legend.position.inside = c(0.55, 0.2)
      ) +
      guides(
        shape = guide_legend(override.aes = list(size = 3.5)),
        fill = guide_legend(override.aes = list(alpha = 1))
      )
}
