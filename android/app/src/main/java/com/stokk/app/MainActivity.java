package com.stokk.app;

import android.os.Bundle;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(AtualizadorPlugin.class);   // atualização do APK (ver AtualizadorPlugin.java)
        super.onCreate(savedInstanceState);
    }
}
