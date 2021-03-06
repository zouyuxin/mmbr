context("Test Single Effect regression")

test_that("mmbr is identical to susieR", with(simulate_univariate(), {
    # Test fixed prior
    A = susieR:::single_effect_regression(y, X, V, residual_variance = 1, prior_weights = NULL, optimize_V = NULL)
    kl = susieR:::SER_posterior_e_loglik(X,y,1,A$alpha*A$mu,A$alpha*A$mu2)- A$loglik
    B = SingleEffectModel(BayesianSimpleRegression)$new(d$n_effect, 1, V)
    d.copy = d$clone(T)
    B$fit(d.copy)
    B$compute_kl(d.copy)
    expect_equal(A$alpha * A$mu, as.vector(B$posterior_b1))
    expect_equal(A$alpha * A$mu2, as.vector(B$posterior_b2))
    expect_equal(A$lbf_model, B$lbf)
    expect_equal(kl, B$kl)
    # Test estimated prior
    A = susieR:::single_effect_regression(y, X, V, residual_variance = 1, prior_weights = NULL, optimize_V = "optim")
    kl = susieR:::SER_posterior_e_loglik(X,y,1,A$alpha*A$mu,A$alpha*A$mu2)- A$loglik
    B = SingleEffectModel(BayesianSimpleRegression)$new(d$n_effect, 1, V)
    d.copy = d$clone(T)
    B$fit(d.copy, estimate_prior_variance_method='optim')
    B$compute_kl(d.copy)
    expect_equal(A$alpha * A$mu, as.vector(B$posterior_b1))
    expect_equal(A$alpha * A$mu2, as.vector(B$posterior_b2))
    expect_equal(A$lbf_model, B$lbf)
    expect_equal(kl, B$kl)
}))

test_that("mmbr is identical to susieR (RSS)", with(simulate_univariate(summary = T), {
  # Test fixed prior
  attr(R, 'eigen') = eigen(R, symmetric = T)
  R = susieR:::set_R_attributes(R, 1e-08)
  attr(R, 'lambda') = 0
  Sigma = susieR:::update_Sigma(R, 1, z)
  A = susieR:::single_effect_regression_rss(z, Sigma, V, prior_weights = NULL, optimize_V = "none")
  kl = susieR:::SER_posterior_e_loglik_rss(R,Sigma,z,A$alpha*A$mu,A$alpha*A$mu2)- A$lbf_model
  B = SingleEffectModel(BayesianSimpleRegression)$new(d$n_effect, 1, V)
  d.copy = d$clone(T)
  B$fit(d.copy)
  B$compute_kl(d.copy)
  expect_equal(A$alpha * A$mu, as.vector(B$posterior_b1))
  expect_equal(A$alpha * A$mu2, as.vector(B$posterior_b2))
  expect_equal(A$lbf_model, B$lbf)
  expect_equal(kl, B$kl)
  # Test estimated prior
  A = susieR:::single_effect_regression_rss(z, Sigma, V, prior_weights = NULL, optimize_V = "optim")
  kl = susieR:::SER_posterior_e_loglik_rss(R,Sigma,z,A$alpha*A$mu,A$alpha*A$mu2)- A$lbf_model
  B = SingleEffectModel(BayesianSimpleRegression)$new(d$n_effect, 1, V)
  d.copy = d$clone(T)
  B$fit(d.copy, estimate_prior_variance_method='optim')
  B$compute_kl(d.copy)
  expect_equal(A$alpha * A$mu, as.vector(B$posterior_b1))
  expect_equal(A$alpha * A$mu2, as.vector(B$posterior_b2))
  expect_equal(A$lbf_model, B$lbf)
  expect_equal(kl, B$kl)
}))