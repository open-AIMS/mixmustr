% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/plotting.R
\name{evaluate_uncertainty}
\alias{evaluate_uncertainty}
\title{Visually inspect uncertainty for input mixing proportion}
\usage{
evaluate_uncertainty(pi, ln_sigma_rho, iter = 10000, seed = 10)
}
\arguments{
\item{pi}{A numeric vector containing mixing proportions
(needs to sum to 1). If named, the function uses the names for plotting
purposes.}

\item{ln_sigma_rho}{A numeric vector containing the uncertainty
around \code{pi} on the log scale.}

\item{iter}{Integer. The number of iterations to run the simulation for.
Defaults to 10,000.}

\item{seed}{Integer. Seed for simulation reproducibility. Defaults to 10.
Defaults to 10.}
}
\value{
A \code{\link[ggplot2]{ggplot}} object representing the faceted
}
\description{
This function plots the expected uncertainty around each input mixing
proportion given its uncertainty on the log scale.
}
\details{
We recognise that choosing the appropriate value for the uncertainty around
data stream 2, \eqn{\sigma_{\text{ln}\rho}}, is not trivial. Therefore, the
MixMustR package offers a simple tool which plots the expected variability
in mixing proportion as a function of an input vector of mixing proportions
from data stream 2 (one from each source), and their respective degrees of
confidence or measurement error. Although the function does not inform the
user what the expected uncertainty for each source and observation should be
(what has to come from expect knowledge), it does allow the user to fine
tune \eqn{\sigma_{\text{ln}\rho}} until the appropriate variability in input
mixing proportions is achieved.
}
\examples{
x = c(0.06, 0.6, 0.04, 0.3)
ln_sigma_x <- rep(1, length(x))
MixMustR::evaluate_uncertainty(x, ln_sigma_x)$plot

}
