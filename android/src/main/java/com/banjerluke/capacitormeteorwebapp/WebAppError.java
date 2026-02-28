package com.banjerluke.capacitormeteorwebapp;

public class WebAppError extends Exception {

    public enum Type {
        INVALID_ASSET_MANIFEST,
        FILE_SYSTEM_ERROR,
        DOWNLOAD_FAILURE,
        UNSUITABLE_ASSET_BUNDLE,
        INITIALIZATION_FAILED,
        BRIDGE_UNAVAILABLE,
        NO_PENDING_VERSION,
        NO_ROOT_URL_CONFIGURED,
        STARTUP_TIMEOUT
    }

    private final Type type;

    public WebAppError(Type type, String message) {
        super(message);
        this.type = type;
    }

    public WebAppError(Type type, String message, Throwable cause) {
        super(message, cause);
        this.type = type;
    }

    public Type getType() {
        return type;
    }
}
