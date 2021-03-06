#' @title SUm of SIngle Effect (SuSiE) regression IBSS algorithm
#' @importFrom R6 R6Class
#' @importFrom progress progress_bar
#' @keywords internal
SuSiE <- R6Class("SuSiE",
  public = list(
    initialize = function(SER,L,estimate_residual_variance=FALSE,
                    compute_objective = TRUE,max_iter=100,tol=1e-3,
                    track_pip=FALSE,track_lbf=FALSE)
    {
        if (!compute_objective) {
            track_pip = TRUE
            estimate_residual_variance = FALSE
        }
        # initialize single effect regression models
        private$L = L
        private$to_estimate_residual_variance = estimate_residual_variance
        private$to_compute_objective = compute_objective
        private$SER = lapply(1:private$L, function(l) SER$clone(deep=T))
        private$sigma2 = SER$residual_variance
        private$elbo = vector()
        private$.niter = max_iter
        private$tol = tol

        if (track_pip) private$.pip_history = list()
        if (track_lbf) private$.lbf_history = list()
    },
    init_coef = function(coef_index, coef_value, p, r) {
        L = length(coef_index)
        if (L <= 0) stop("Need at least one non-zero effect")
        if (L > private$L) stop("Cannot initialize more effects than the current model allows")
        if (any(which(apply(coef_value,1,sum)==0))) stop("Input coef_value must be at least one non-zero item per row")
        if (L != nrow(coef_value)) stop("Inputs coef_index and coef_value must of the same length")
        if (max(coef_index)>p) stop("Input coef_index exceeds the boundary of p")
        for (i in 1:L) {
            mu = matrix(0, p, r)
            mu[coef_index[i], ] = coef_value[i,]
            private$SER[[i]]$mu = mu
        }
    },
    fit = function(d, prior_weights=NULL, estimate_prior_variance_method=NULL, verbose=TRUE) {
        if (verbose) pb = progress_bar$new(format = "[:spin] Iteration :iteration (diff = :delta) :elapsed",
                                    clear = TRUE, total = private$.niter, show_after = .5)
        else pb = null_progress_bar$new()
        for (i in 1:private$.niter) {
            private$save_history()
            fitted = d$compute_Xb(Reduce(`+`, lapply(1:private$L, function(l) private$SER[[l]]$posterior_b1)))
            d$compute_residual(fitted)
            for (l in 1:private$L) {
                d$add_to_residual(private$SER[[l]]$predict(d))
                if (private$to_estimate_residual_variance) private$SER[[l]]$residual_variance = private$sigma2
                private$SER[[l]]$fit(d, prior_weights=prior_weights, estimate_prior_variance_method=estimate_prior_variance_method)
                if (private$to_compute_objective) private$SER[[l]]$compute_kl(d)
                d$remove_from_residual(private$SER[[l]]$predict(d))
            }
            if (private$to_compute_objective)
              private$compute_objective(d)
            private$.convergence = private$check_convergence(i)
            if (private$.convergence$converged) {
                private$save_history()
                pb$tick(private$.niter)
                private$.niter = i
                break
            }
            if (private$to_estimate_residual_variance)
              private$estimate_residual_variance(d)

            pb$tick(tokens = list(delta=sprintf(private$.convergence$delta, fmt = '%#.1e'), iteration=i))
        }
    },
    get_objective = function(dump = FALSE) {
        if (length(private$elbo) == 0) return(NA)
        if (!all(diff(private$elbo) >= 0)) {
            warning('Objective is not non-decreasing')
            dump = TRUE
        }
        if (dump) return(private$elbo)
        else return(private$elbo[private$.niter])
    }
  ),
  active = list(
    niter = function() private$.niter,
    convergence = function() private$.convergence,
    # get prior effect size, because it might be updated during iterations
    prior_variance = function() sapply(1:private$L, function(l) private$SER[[l]]$prior_variance),
    residual_variance = function() private$sigma2,
    kl = function() {
        if (!private$to_compute_objective) NA
        else sapply(1:private$L, function(l) private$SER[[l]]$kl)
    },
    # posterior inclusion probability, J by L matrix
    pip = function() do.call(cbind, lapply(1:private$L, function(l) private$SER[[l]]$pip)),
    lbf = function() sapply(1:private$L, function(l) private$SER[[l]]$lbf),
    pip_history = function() lapply(ifelse(private$.niter>1, 2, 1):length(private$.pip_history), function(i) private$.pip_history[[i]]),
    lbf_history = function() lapply(ifelse(private$.niter>1, 2, 1):length(private$.lbf_history), function(i) private$.lbf_history[[i]]),
    posterior_b1 = function() lapply(1:private$L, function(l) private$SER[[l]]$posterior_b1),
    posterior_b2 = function() lapply(1:private$L, function(l) private$SER[[l]]$posterior_b2),
    lfsr = function() lapply(1:private$L, function(l) private$SER[[l]]$lfsr),
    mixture_posterior_weights = function() lapply(1:private$L, function(l) private$SER[[l]]$mixture_posterior_weights)
  ),
  private = list(
    to_estimate_residual_variance = NULL,
    to_compute_objective = NULL,
    L = NULL,
    SER = NULL, # Single effect regression models
    elbo = NULL, # Evidence lower bound
    null_index = NULL, # index of null effect intentially added
    .niter = NULL,
    .convergence = NULL,
    .pip_history = NULL, # keep track of pip
    .lbf_history = NULL, # keep track of lbf
    tol = NULL, # tolerance level for convergence
    sigma2 = NULL, # residual variance
    essr = NULL,
    check_convergence = function(n) {
        if (n<=1) {
            return (list(delta=Inf, converged=FALSE))
        } else {
            if (private$to_compute_objective)
                delta = private$elbo[n] - private$elbo[n-1]
            else
                delta = max(abs(private$.pip_history[[n]] - private$.pip_history[[n-1]]))
            return (list(delta=delta, converged=(delta < private$tol)))
        }
    },
    compute_objective = function(d) {
        if (d$Y_has_missing && private$to_compute_objective) {
            warning("ELBO calculation with missing data in Y has not been implemented.")
            private$to_compute_objective = FALSE
        }
        if (private$to_compute_objective) {
            if (is.matrix(private$SER[[1]]$residual_variance)) {
                expected_loglik = private$compute_expected_loglik_multivariate(d)
            } else {
                expected_loglik = private$compute_expected_loglik_univariate(d)
            }
            elbo = expected_loglik - Reduce('+', self$kl)
        } else {
            elbo = NA
        }
        private$elbo = c(private$elbo, elbo)
    },
    # expected loglikelihood for SuSiE model
    compute_expected_loglik_univariate = function(d) {
        n = d$n_sample
        residual_variance = private$sigma2
        essr = private$compute_expected_sum_squared_residuals_univariate(d)
        return(-(n/2) * log(2*pi* residual_variance) - (1/(2*residual_variance)) * essr)
    },
    compute_expected_loglik_multivariate = function(d) {
      expected_loglik = -(d$n_sample * d$n_condition / 2) * log(2*pi) - d$n_sample / 2 * log(det(private$sigma2))
      essr = private$compute_expected_sum_squared_residuals_multivariate(d)
      return(expected_loglik - 0.5 * essr)
    },
    estimate_residual_variance = function(d) {
        if (is.matrix(private$SER[[1]]$residual_variance)) {
            # FIXME: to implement estimating a vector of length R, or even a scalar
            E1 = lapply(1:length(private$SER), function(l) t(private$SER[[l]]$posterior_b1) %*% d$XtX %*% private$SER[[l]]$posterior_b1)
            E1 = crossprod(d$residual) - Reduce('+', E1)
            private$sigma2 = (E1 + Reduce('+', lapply(1:length(private$SER), function(l) private$SER[[l]]$bxxb))) / d$n_sample
        } else {
            private$sigma2 = private$compute_expected_sum_squared_residuals_univariate(d) / d$n_sample
        }
    },
    # expected squared residuals
    compute_expected_sum_squared_residuals_univariate = function(d) {
      Eb1 = t(do.call(cbind, self$posterior_b1))
      Eb2 = t(do.call(cbind, self$posterior_b2))
      if (inherits(d, "RSSData")) {
        # RSSData is inherited from DenseData
        # actually code below will also work for DenseData
        # (that is why there is no need to treat them separately in multivarite computation)
        # here we separate them out to agree with SuSiE RSS derivations as a test
        XB2 = sum((Eb1 %*% d$XtX) * Eb1)
        return(as.numeric(crossprod(d$residual) - XB2 + sum(d$X2_sum*t(Eb2))))
      } else {
        # full data, DenseData object
        Xr = d$compute_MXt(Eb1)
        Xrsum = colSums(Xr)
        return(sum((d$Y-Xrsum)^2) - sum(Xr^2) + sum(d$X2_sum*t(Eb2)))
      }
    },
    compute_expected_sum_squared_residuals_multivariate = function(d) {
      v_inv = private$SER[[1]]$residual_variance_inv
      E1 = sapply(1:length(private$SER), function(l) tr(v_inv %*% t(private$SER[[l]]$posterior_b1) %*% d$XtX %*% private$SER[[l]]$posterior_b1))
      E1 = tr(v_inv%*%crossprod(d$residual)) - sum(E1)
      return(E1 + Reduce('+', lapply(1:length(private$SER), function(l) private$SER[[l]]$vbxxb)))
    },
    save_history = function() {
        if (!is.null(private$.pip_history)) {
            private$.pip_history[[length(private$.pip_history) + 1]] = self$pip
        }
        if (!is.null(private$.lbf_history)) {
            private$.lbf_history[[length(private$.lbf_history) + 1]] = self$lbf
        }
    }
  )
)