package com.banjerluke.capacitormeteorwebapp;

import com.getcapacitor.Logger;

public class CapacitorMeteorWebApp {

    public String echo(String value) {
        Logger.info("Echo", value);
        return value;
    }
}
