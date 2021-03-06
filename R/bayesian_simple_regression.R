#' @title Bayesian multiple regression object
#' @importFrom R6 R6Class
#' @keywords internal
BayesianSimpleRegression <- R6Class("BayesianSimpleRegression",
  public = list(
    initialize = function(J, residual_variance, prior_variance) {
      private$J = J
      private$.prior_variance = prior_variance
      private$.residual_variance = residual_variance
      private$.posterior_b1 = matrix(0, J, 1)
    },
    fit = function(d, prior_weights = NULL, use_residual = FALSE, save_summary_stats = FALSE, estimate_prior_variance_method = NULL) {
      # d: data object
      # use_residual: fit with residual instead of with Y,
      # a special feature for when used with SuSiE algorithm
      if (use_residual) XtY = d$XtR
      else XtY = d$XtY
      # OLS estimates
      bhat = XtY / d$X2_sum
      bhat[which(is.nan(bhat))] = 0
      sbhat2 = private$.residual_variance / d$X2_sum
      if (save_summary_stats) {
        private$.bhat = bhat
        private$.sbhat = sqrt(sbhat2)
        private$.sbhat[which(is.nan(private$.sbhat) | is.infinite(private$.sbhat))] = 1E3
      }
      # deal with prior variance: can be "estimated" across effects
      if(!is.null(estimate_prior_variance_method)) {
          if (is.null(prior_weights)) prior_weights = rep(1/private$J, private$J)
        private$.prior_variance = private$estimate_prior_variance(bhat,sbhat2,prior_weights,method=estimate_prior_variance_method)
      }
      # posterior
      post_var = (1/private$.prior_variance + d$X2_sum/private$.residual_variance)^(-1) # posterior variance
      private$.posterior_b1 = (1/private$.residual_variance) * post_var * XtY
      private$.posterior_b2 = post_var + private$.posterior_b1^2 # second moment
      # Bayes factor
      private$.lbf = dnorm(bhat,0,sqrt(private$.prior_variance+sbhat2),log=TRUE) - dnorm(bhat,0,sqrt(sbhat2),log=TRUE)
      if (!is.null(ncol(private$.lbf)) && ncol(private$.lbf) == 1)
        private$.lbf = as.vector(private$.lbf)
      private$.lbf[sbhat2==Inf] = 0
    }
  ),
  active = list(
    loglik_null = function() private$.loglik_null,
    posterior_b1 = function() private$.posterior_b1,
    posterior_b2 = function() private$.posterior_b2,
    lbf = function() private$.lbf,
    bhat = function() private$.bhat,
    sbhat = function() private$.sbhat,
    prior_variance = function() private$.prior_variance,
    residual_variance = function(v) {
      if (missing(v)) private$.residual_variance
      else private$.residual_variance = v
    }
  ),
  private = list(
    J = NULL,
    .bhat = NULL,
    .sbhat = NULL,
    .prior_variance = NULL, # prior on effect size
    .residual_variance = NULL,
    .loglik_null = NULL,
    .lbf = NULL, # log Bayes factor
    .posterior_b1 = NULL, # posterior first moment
    .posterior_b2 = NULL, # posterior second moment
    loglik = function(V,betahat,shat2,prior_weights) {
      lbf = dnorm(betahat,0,sqrt(V+shat2),log=TRUE) - dnorm(betahat,0,sqrt(shat2),log=TRUE)
      #log(bf) on each SNP
      lbf[shat2==Inf] = 0 # deal with special case of infinite shat2 (eg happens if X does not vary)
      return(compute_weighted_sum(lbf, prior_weights)$log_sum)
    },
    neg_loglik_logscale = function(lV,betahat,shat2,prior_weights){
      return(-1 * private$loglik(exp(lV),betahat,shat2,prior_weights))
    },
    # vector of gradients of logBF_j for each j, with respect to prior variance V
    lbf_grad = function(V,sbhat2,T2){
      l = 0.5* (1/(V+sbhat2)) * ((sbhat2/(V+sbhat2))*T2-1)
      l[is.nan(l)] = 0
      return(l)
    },
    loglik_grad = function(V,bhat,sbhat2,prior_weights) {
      #log(bf) on each effect
      lbf = dnorm(bhat,0,sqrt(V+sbhat2),log=TRUE) - dnorm(bhat,0,sqrt(sbhat2),log=TRUE)
      lbf[sbhat2==Inf] = 0 # deal with special case of infinite sbhat2 (eg happens if X does not vary)
      alpha = compute_weighted_sum(lbf, prior_weights)$weights
      sum(alpha*private$lbf_grad(V,sbhat2,bhat^2/sbhat2))
    },
    # define gradient as function of lV:=log(V)
    # to improve numerical optimization
    negloglik_grad_logscale = function(lV,betahat,shat2,prior_weights) {
      -exp(lV)*private$loglik_grad(exp(lV),betahat,shat2,prior_weights)
    },
    estimate_prior_variance = function(betahat,shat2,prior_weights, method=c('optim', 'uniroot', 'simple')) {
      if(method=="optim"){
        lV = optim(par=log(max(c(betahat^2-shat2, 1), na.rm = TRUE)), fn=private$neg_loglik_logscale, betahat=betahat, shat2=shat2, prior_weights = prior_weights, method='Brent', lower = -30, upper = 15)$par
        V = exp(lV)
      } else if (method == 'uniroot'){
        V.u = uniroot(private$negloglik_grad_logscale,c(-10,10),extendInt = "upX",betahat=betahat,shat2=shat2,prior_weights=prior_weights)
        V = exp(V.u$root)
      } else if (method == 'simple'){
        V = private$.prior_variance
      }
      if(private$loglik(0,betahat,shat2,prior_weights) >= private$loglik(V,betahat,shat2,prior_weights)) V=0 # set V exactly 0 if that beats the numerical value
      return(V)
    }
  )
)