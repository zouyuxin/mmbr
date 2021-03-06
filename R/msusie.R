#' @title SUm of Single Effect (SuSiE) Regression of multivariate Y on X
#' @details Performs Bayesian multiple linear regression of Y on X.
#' That is, this function
#' fits the regression model Y= sum_l Xb_l + e, where elements of e are iid N(0,residual_variance) and the
#' sum_l b_l is a p vector of effects to be estimated.
#' The assumption is that each b_l has exactly one non-zero element, with all elements
#' equally likely to be non-zero.
#' @param X an n by p matrix of covariates
#' @param Y an n vector
#' @param L maximum number of non-zero effects
#' @param prior_variance Can be 1) a vector of length L, or a scalar, for scaled prior variance when Y is univariate (equivalent to `susieR::susie`); 2) a matrix for simple Multivariate regression or 3) a MASH fit that contains an array of prior covariance matrices and their weights
#' @param residual_variance the residual variance (defaults to sample variance of Y)
#' @param prior_weights a p vector of prior probability that each element is non-zero
#' @param standardize logical flag (default=TRUE) for whether to standardize columns of X to unit variance prior to fitting.
#' If you do not standardize you may need
#' to think more carefully about specifying the scale of prior variance.
#' Whatever the value of standardize, the coefficients (returned from `coef`) are for X on the original input scale.
#' Any column of X that has zero variance is not standardized, but left as is.
#' @param intercept Should intercept be fitted (default=TRUE) or set to zero (FALSE). The latter is generally not recommended.
#' @param estimate_residual_variance indicates whether to estimate residual variance (currently only works for univariate Y input)
#' @param estimate_prior_variance indicates whether to estimate prior (currently only works for univariate Y and for multivariate Y when prior is a single matrix)
#' @param estimate_prior_method the method used for estimating prior variance: "optim", "uniroot" and "em" for univariate Y, "optim" and "simple" for multivariate Y.
#' @param precompute_covariances if TRUE, precomputes various covariance quantities to speed up computations at the cost of increased memory usage
#' @param s_init a previous susie fit with which to initialize
#' @param coverage coverage of confident sets. Default to 0.95 for 95\% credible interval.
#' @param min_abs_corr minimum of absolute value of correlation allowed in a credible set.
#' Default set to 0.5 to correspond to squared correlation of 0.25,
#' a commonly used threshold for genotype data in genetics studies.
#' @param compute_univariate_zscore if TRUE outputs z-score from per variable univariate regression
#' @param max_iter maximum number of iterations to perform
#' @param tol convergence tolerance
#' @param verbose if TRUE outputs some progress messages
#' @param track_fit add an attribute \code{trace} to output that saves some current quantities of all iterations
#' @return a susie fit, which is a list with some or all of the following elements\cr
#' \item{alpha}{an L by p matrix of posterior inclusion probabilites}
#' \item{b1}{an L by p matrix of posterior means (conditional on inclusion)}
#' \item{b2}{an L by p matrix of posterior second moments (conditional on inclusion)}
#' \item{KL}{an L vector of KL divergence}
#' \item{lbf}{an L vector of logBF}
#' \item{sigma2}{residual variance}
#' \item{V}{prior variance}
#' \item{elbo}{a vector of values of elbo achieved (objective function)}
#' \item{niter}{number of iterations took for convergence}
#' \item{convergence}{convergence status}
#' \item{sets}{a list of `cs`, `purity` and selected `cs_index`}
#' \item{pip}{a vector of posterior inclusion probability}
#' \item{walltime}{records runtime of the fitting algorithm}
#' \item{z}{a vector of univariate z-scores}
#' @examples
#' set.seed(1)
#' n = 1000
#' p = 1000
#' beta = rep(0,p)
#' beta[1:4] = 1
#' X = matrix(rnorm(n*p),nrow=n,ncol=p)
#' y = X %*% beta + rnorm(n)
#' res = msusie(X,y,L=10)
#'
#' @importFrom stats var
#' @importFrom susieR susie_get_cs susie_get_pip
#' @export
msusie = function(X,Y,L=10,
                 prior_variance=0.2,
                 residual_variance=NULL,
                 prior_weights=NULL,
                 standardize=TRUE,intercept=TRUE,
                 estimate_residual_variance=TRUE,
                 estimate_prior_variance=FALSE,
                 estimate_prior_method='optim',
                 compute_objective=FALSE,
                 s_init = NULL,coverage=0.95,min_abs_corr=0.5,
                 compute_univariate_zscore = FALSE,
                 precompute_covariances = FALSE,
                 max_iter=100,tol=1e-3,
                 verbose=TRUE,track_fit=FALSE) {
  if (is.null(prior_weights)) prior_weights = c(rep(1/ncol(X), ncol(X)))
  else prior_weights = prior_weights / sum(prior_weights)

  data = DenseData$new(X, Y, intercept, standardize)
  if (is.null(residual_variance)) {
    if (data$n_condition > 1) {
      if (!data$Y_has_missing) residual_variance = cov(Y)
      else stop("Unspecified residual_variance is not allowed in the presence of missing data in Y")
    }
    else residual_variance = var(Y, na.rm=T)
  }
  #
  s = mmbr_core(data, s_init, L, residual_variance, prior_variance, prior_weights,
            estimate_residual_variance, estimate_prior_variance, estimate_prior_method,
            precompute_covariances, compute_objective, max_iter, tol, track_fit, verbose)
  # CS and PIP
  if (!is.null(coverage) && !is.null(min_abs_corr)) {
    s$null_index = -9
    s$sets = susie_get_cs(s, coverage=coverage, X=X, min_abs_corr=min_abs_corr)
    s$pip = susie_get_pip(s)
    s$null_index = NULL
  }
  # report z-scores from univariate regression
  if (compute_univariate_zscore) {
    s$z = susieR:::calc_z(X,Y,center=intercept,scale=standardize)
  }
  return(s)
}

#' @title SUm of Single Effect (SuSiE) Regression using Summary Statistics Z and R
#' @param Z a J by R matrix of z scores
#' @param R a J by J LD matrix
#' @param L maximum number of non-zero effects
#' @param prior_variance Can be 1) a vector of length L, or a scalar, for scaled prior variance when Y is univariate (equivalent to `susieR::susie`); 2) a matrix for simple Multivariate regression or 3) a MASH fit that contains an array of prior covariance matrices and their weights
#' @param residual_variance the residual variance (defaults to 1)
#' @param prior_weights a p vector of prior probability that each element is non-zero
#' @param estimate_residual_variance indicates whether to estimate residual variance (currently only works for univariate Y input)
#' @param estimate_prior_variance indicates whether to estimate prior (currently only works for univariate Y and for multivariate Y when prior is a single matrix)
#' @param estimate_prior_method the method used for estimating prior variance: "optim", "uniroot" and "em" for univariate Y, "optim" and "simple" for multivariate Y.
#' @param s_init a previous susie fit with which to initialize
#' @param coverage coverage of confident sets. Default to 0.95 for 95\% credible interval.
#' @param min_abs_corr minimum of absolute value of correlation allowed in a credible set.
#' Default set to 0.5 to correspond to squared correlation of 0.25,
#' a commonly used threshold for genotype data in genetics studies.
#' @param max_iter maximum number of iterations to perform
#' @param tol convergence tolerance
#' @param z_thresh the z score threshold below which to call an effect null
#' @param verbose if TRUE outputs some progress messages
#' @param track_fit add an attribute \code{trace} to output that saves some current quantities of all iterations
#' @return a susie fit, which is a list with some or all of the following elements\cr
#' \item{alpha}{an L by p matrix of posterior inclusion probabilites}
#' \item{b1}{an L by p matrix of posterior means (conditional on inclusion)}
#' \item{b2}{an L by p matrix of posterior second moments (conditional on inclusion)}
#' \item{KL}{an L vector of KL divergence}
#' \item{lbf}{an L vector of logBF}
#' \item{sigma2}{residual variance}
#' \item{V}{prior variance}
#' \item{elbo}{a vector of values of elbo achieved (objective function)}
#' \item{niter}{number of iterations took for convergence}
#' \item{convergence}{convergence status}
#' \item{sets}{a list of `cs`, `purity` and selected `cs_index`}
#' \item{pip}{a vector of posterior inclusion probability}
#' \item{walltime}{records runtime of the fitting algorithm}
#' \item{z}{a vector of univariate z-scores}
#' @examples
#' set.seed(1)
#' n = 1000
#' p = 1000
#' beta = rep(0,p)
#' beta[1:4] = 1
#' X = matrix(rnorm(n*p),nrow=n,ncol=p)
#' y = X %*% beta + rnorm(n)
#' R = t(X) %*% X
#' z = susieR:::calc_z(X,y)
#' res = msusie_rss(z,R,L=10)
#'
#' @importFrom stats var
#' @importFrom susieR susie_get_cs susie_get_pip
#' @export
msusie_rss = function(Z,R,L=10,r_tol = 1e-08,
                      prior_variance=50,
                      residual_variance=NULL,
                      prior_weights=NULL,
                      estimate_residual_variance=TRUE,
                      estimate_prior_variance=FALSE,
                      estimate_prior_method='optim',
                      compute_objective=FALSE,
                      precompute_covariances = FALSE,
                      s_init = NULL,coverage=0.95,min_abs_corr=0.5,
                      max_iter=100,tol=1e-3,z_thresh = 2,
                      verbose=TRUE,track_fit=FALSE) {
  if (is.null(prior_weights)) prior_weights = c(rep(1/nrow(R), nrow(R)))
  else prior_weights = prior_weights / sum(prior_weights)

  data = RSSData$new(Z, R, r_tol)
  if (is.null(residual_variance)) {
    if (data$n_condition > 1) {
      max_absz = apply(abs(data$XtY),1, max)
      nullish = which(max_absz < z_thresh)
      if(length(nullish)<data$n_condition){
        stop("not enough null data to estimate null correlation")
      }
      nullish_z = data$XtY[nullish,]
      residual_variance = cor(nullish_z)
    }
    else residual_variance = 1
  }
  #
  s = mmbr_core(data, s_init, L, residual_variance, prior_variance, prior_weights,
                estimate_residual_variance, estimate_prior_variance, estimate_prior_method,
                precompute_covariances, compute_objective, max_iter, tol, track_fit, verbose)
  # CS and PIP
  if (!is.null(coverage) && !is.null(min_abs_corr)) {
    s$null_index = -9
    s$sets = susie_get_cs(s, coverage=coverage, Xcorr=data$XtX, min_abs_corr=min_abs_corr)
    s$pip = susie_get_pip(s)
    s$null_index = NULL
  }
  return(s)
}


#' @title Core MMBR code
#' @keywords internal
mmbr_core = function(data, s_init, L, residual_variance, prior_variance, prior_weights,
            estimate_residual_variance, estimate_prior_variance, estimate_prior_method,
            precompute_covariances, compute_objective, max_iter, tol, track_fit, verbose) {
  start_time = proc.time()
  if (is.numeric(prior_variance) && !is.matrix(prior_variance))
    residual_variance = as.numeric(residual_variance)
  if (is.matrix(residual_variance)) {
    if (any(is.na(diag(residual_variance))))
      stop("Diagonal of residual_variance cannot be NA")
    residual_variance[which(is.na(residual_variance))] = 0
    mashr:::check_positive_definite(residual_variance)
  } else {
    if (is.na(residual_variance) || is.infinite(residual_variance))
      stop("Invalid residual_variance")
  }
  # for now the type of prior_variance controls the type of regression
  if (is.numeric(prior_variance)) {
    if (data$n_condition > 1 && !is.matrix(prior_variance))
      stop(paste("prior variance cannot be a number for multivariate analysis with", data$n_condition, "response variables."))
    if (is.matrix(prior_variance)) {
      base = BayesianMultivariateRegression
    } else {
      base = BayesianSimpleRegression
      # Here prior variance is scaled prior variance
      if (is.matrix(residual_variance)) {
        if (!(nrow(residual_variance) == 1 && (ncol(residual_variance))))
          stop("residual_variance should be a scalar.")
        residual_variance = residual_variance[1,1]
      }
      prior_variance = prior_variance * residual_variance
    }
  } else {
    # FIXME: check prior_variance is valid MASH object
    if (prior_variance$n_condition != data$n_condition) stop("Dimension mismatch between input prior covariance and response variable data.")
    base = MashRegression
    if (data$Y_has_missing || precompute_covariances)
      prior_variance$precompute_cov_matrices(data, residual_variance)
    residual_variance = as.matrix(residual_variance)
  }
  if (!estimate_prior_variance) estimate_prior_method = NULL
  # Below are the core computations
  SER_model = SingleEffectModel(base)$new(data$n_effect, residual_variance, prior_variance)
  SuSiE_model = SuSiE$new(SER_model, L, estimate_residual_variance, compute_objective, max_iter, tol, track_pip=track_fit, track_lbf=track_fit)
  if (!is.null(s_init)) SuSiE_model$init_coef(s_init$coef_index, s_init$coef_value, data$n_effect, data$n_condition)
  SuSiE_model$fit(data, prior_weights, estimate_prior_method, verbose)
  s = report_susie_model(data, SuSiE_model, estimate_prior_variance)
  ## clean up prior object
  if ('R6' %in% class(prior_variance)) prior_variance$remove_precomputed()
  s$walltime = proc.time() - start_time
  return(s)
}