package com.banjerluke.capacitormeteorwebapp;

class RetryStrategy {
    private final double quickRetryIntervalSeconds;
    private final double maximumIntervalSeconds;

    RetryStrategy() {
        this(0.1d, 30.0d);
    }

    RetryStrategy(double quickRetryIntervalSeconds, double maximumIntervalSeconds) {
        this.quickRetryIntervalSeconds = quickRetryIntervalSeconds;
        this.maximumIntervalSeconds = maximumIntervalSeconds;
    }

    double retryIntervalForAttempt(long numberOfAttempts) {
        if (numberOfAttempts <= 0) {
            return quickRetryIntervalSeconds;
        }

        double n = (double) (numberOfAttempts - 1);
        double interval = 1.0d + (n * (n + 1.0d) / 2.0d);
        return Math.min(interval, maximumIntervalSeconds);
    }
}
