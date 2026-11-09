package com.stokk.app;

import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import androidx.core.content.FileProvider;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;

/**
 * Atualização do APK fora da Play Store.
 *  info()             -> versão instalada (codigo = versionCode) e se o app já pode instalar APK ("pode")
 *  abrirPermissao()   -> abre a tela do Android "Permitir deste app" (instalar apps desconhecidos)
 *  baixarEInstalar()  -> baixa o APK (https), confere o SHA-256 e abre o instalador do Android.
 *                        Evento "progresso" {pct} durante o download.
 * O Android só instala por cima se o APK for assinado com a MESMA chave do app instalado.
 */
@CapacitorPlugin(name = "Atualizador")
public class AtualizadorPlugin extends Plugin {

    @PluginMethod
    public void info(PluginCall call) {
        try {
            Context ctx = getContext();
            PackageInfo pi = ctx.getPackageManager().getPackageInfo(ctx.getPackageName(), 0);
            long codigo = Build.VERSION.SDK_INT >= 28 ? pi.getLongVersionCode() : pi.versionCode;
            JSObject r = new JSObject();
            r.put("codigo", codigo);
            r.put("versao", pi.versionName);
            r.put("pode", Build.VERSION.SDK_INT < 26 || ctx.getPackageManager().canRequestPackageInstalls());
            call.resolve(r);
        } catch (Exception e) {
            call.reject("Não consegui ler a versão instalada.");
        }
    }

    @PluginMethod
    public void abrirPermissao(PluginCall call) {
        try {
            Context ctx = getContext();
            Intent i = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + ctx.getPackageName()));
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            ctx.startActivity(i);
            call.resolve();
        } catch (Exception e) {
            call.reject("Não consegui abrir a tela de permissão.");
        }
    }

    @PluginMethod
    public void baixarEInstalar(final PluginCall call) {
        final String url = call.getString("url");
        final String sha = call.getString("sha256");
        if (url == null || !url.startsWith("https://")) {
            call.reject("Endereço de download inválido.");
            return;
        }
        new Thread(new Runnable() {
            @Override
            public void run() {
                File arquivo = null;
                try {
                    Context ctx = getContext();
                    File pasta = new File(ctx.getCacheDir(), "update");
                    if (!pasta.exists()) pasta.mkdirs();
                    File[] antigos = pasta.listFiles();
                    if (antigos != null) for (File f : antigos) f.delete();
                    arquivo = new File(pasta, "STOKK.apk");

                    HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
                    c.setInstanceFollowRedirects(true);
                    c.setConnectTimeout(20000);
                    c.setReadTimeout(30000);
                    if (c.getResponseCode() != 200) {
                        call.reject("O servidor respondeu " + c.getResponseCode() + ".");
                        return;
                    }
                    long total = c.getContentLengthLong();
                    MessageDigest md = MessageDigest.getInstance("SHA-256");
                    long lido = 0;
                    int ultimo = -1;
                    byte[] buf = new byte[32768];
                    InputStream in = c.getInputStream();
                    FileOutputStream out = new FileOutputStream(arquivo);
                    try {
                        int n;
                        while ((n = in.read(buf)) > 0) {
                            out.write(buf, 0, n);
                            md.update(buf, 0, n);
                            lido += n;
                            if (total > 0) {
                                int pct = (int) (lido * 100 / total);
                                if (pct != ultimo) {
                                    ultimo = pct;
                                    JSObject p = new JSObject();
                                    p.put("pct", pct);
                                    notifyListeners("progresso", p);
                                }
                            }
                        }
                    } finally {
                        out.close();
                        in.close();
                    }
                    if (total > 0 && lido != total) {
                        arquivo.delete();
                        call.reject("Download incompleto. Tente de novo.");
                        return;
                    }
                    StringBuilder hex = new StringBuilder();
                    for (byte b : md.digest()) hex.append(String.format("%02x", b));
                    if (sha == null || sha.length() != 64 || !hex.toString().equalsIgnoreCase(sha)) {
                        arquivo.delete();
                        call.reject("O arquivo baixado não confere com o esperado. Não foi instalado.");
                        return;
                    }

                    final Uri uri = FileProvider.getUriForFile(ctx, ctx.getPackageName() + ".fileprovider", arquivo);
                    final Intent i = new Intent(Intent.ACTION_VIEW);
                    i.setDataAndType(uri, "application/vnd.android.package-archive");
                    i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
                    getActivity().runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            try {
                                getContext().startActivity(i);
                                call.resolve();
                            } catch (Exception e) {
                                call.reject("Não consegui abrir o instalador.");
                            }
                        }
                    });
                } catch (Exception e) {
                    if (arquivo != null) arquivo.delete();
                    call.reject("Falha no download: " + e.getMessage());
                }
            }
        }).start();
    }
}
