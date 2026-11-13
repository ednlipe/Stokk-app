package com.stokk.app;

import androidx.annotation.NonNull;
import androidx.biometric.BiometricManager;
import androidx.biometric.BiometricPrompt;
import androidx.core.content.ContextCompat;
import androidx.fragment.app.FragmentActivity;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

/**
 * Bloqueio do app por biometria (digital/rosto) ou, se não der, pelo PIN/padrão/senha do celular.
 *  disponivel() -> { ok, codigo }  ok = o celular tem biometria cadastrada OU bloqueio de tela (BiometricManager)
 *  autenticar() -> abre a confirmação do sistema (BiometricPrompt, direto na tela do app, sem outra Activity).
 *                  Sucesso = resolve; erro/cancelamento = reject com codigo do Android (ex.: 10 = o usuário cancelou).
 */
@CapacitorPlugin(name = "Biometria")
public class BiometriaPlugin extends Plugin {

    // BIOMETRIC_WEAK + credencial do aparelho (PIN/padrão/senha). STRONG + credencial não funciona no Android 9-10.
    private static final int AUTENTICADORES =
        BiometricManager.Authenticators.BIOMETRIC_WEAK | BiometricManager.Authenticators.DEVICE_CREDENTIAL;

    @PluginMethod
    public void disponivel(PluginCall call) {
        try {
            int r = BiometricManager.from(getContext()).canAuthenticate(AUTENTICADORES);
            JSObject o = new JSObject();
            o.put("ok", r == BiometricManager.BIOMETRIC_SUCCESS);
            o.put("codigo", r);
            call.resolve(o);
        } catch (Exception e) {
            call.reject("disponivel falhou: " + e.getMessage());
        }
    }

    @PluginMethod
    public void autenticar(final PluginCall call) {
        final FragmentActivity act = getActivity();
        if (act == null) {
            call.reject("sem tela ativa");
            return;
        }
        final String subtitulo = call.getString("subtitulo", "Confirme que é você");
        act.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                try {
                    BiometricPrompt.PromptInfo info = new BiometricPrompt.PromptInfo.Builder()
                        .setTitle("STOKK")
                        .setSubtitle(subtitulo)
                        .setAllowedAuthenticators(AUTENTICADORES)
                        .build();
                    BiometricPrompt prompt = new BiometricPrompt(act, ContextCompat.getMainExecutor(act),
                        new BiometricPrompt.AuthenticationCallback() {
                            @Override
                            public void onAuthenticationError(int errorCode, @NonNull CharSequence errString) {
                                call.reject(errString.toString(), String.valueOf(errorCode));
                            }

                            @Override
                            public void onAuthenticationSucceeded(@NonNull BiometricPrompt.AuthenticationResult result) {
                                call.resolve();
                            }
                        });
                    prompt.authenticate(info);
                } catch (Exception e) {
                    call.reject("não abriu a confirmação: " + e.getMessage());
                }
            }
        });
    }
}
