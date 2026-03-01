package com.banjerluke.capacitormeteorwebapp;

import org.junit.After;
import org.junit.Test;

import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.InputStream;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class BundleOrganizerTest {

    private final File targetDirectory = new File(System.getProperty("java.io.tmpdir"), "bundle-organizer-test-" + System.nanoTime());

    @After
    public void cleanup() {
        FileOps.deleteRecursively(targetDirectory);
    }

    @Test
    public void organizeBundleInjectsShimAndCopiesAssets() throws Exception {
        String manifest = manifestForEntry("app/main.js", "/app/main.js", "0123456789012345678901234567890123456789");
        String runtimeConfig = "{\"ROOT_URL\":\"https://example.com\",\"appId\":\"test-app\",\"autoupdateVersionCordova\":\"v1\"}";
        String indexHtml = "<html><head><script>__meteor_runtime_config__ = JSON.parse(decodeURIComponent(\""
            + URLEncoder.encode(runtimeConfig, "UTF-8")
            + "\"))</script></head><body></body></html>";

        Map<String, byte[]> files = new HashMap<>();
        files.put("program.json", manifest.getBytes(StandardCharsets.UTF_8));
        files.put("index.html", indexHtml.getBytes(StandardCharsets.UTF_8));
        files.put("app/main.js", "console.log('ok');".getBytes(StandardCharsets.UTF_8));

        AssetBundle bundle = AssetBundle.fromReader("test", path -> openFromMap(files, path), null);

        BundleOrganizer.organizeBundle(bundle, targetDirectory);

        File organizedIndex = new File(targetDirectory, "index.html");
        File organizedJs = new File(targetDirectory, "app/main.js");

        assertTrue(organizedIndex.exists());
        assertTrue(organizedJs.exists());
        String organizedIndexContent = new String(java.nio.file.Files.readAllBytes(organizedIndex.toPath()), StandardCharsets.UTF_8);
        assertTrue(organizedIndexContent.contains("window.WebAppLocalServer"));
    }

    @Test
    public void validateBundleDetectsTraversal() throws Exception {
        String manifest = manifestForEntry("../bad.js", "/../bad.js", "0123456789012345678901234567890123456789");

        Map<String, byte[]> files = new HashMap<>();
        files.put("program.json", manifest.getBytes(StandardCharsets.UTF_8));
        files.put("index.html", "<html></html>".getBytes(StandardCharsets.UTF_8));

        AssetBundle bundle = AssetBundle.fromReader("test", path -> openFromMap(files, path), null);
        List<String> errors = BundleOrganizer.validateBundleOrganization(bundle);

        assertFalse(errors.isEmpty());
    }

    private static InputStream openFromMap(Map<String, byte[]> files, String path) throws java.io.IOException {
        byte[] data = files.get(path);
        if (data == null) {
            throw new FileNotFoundException(path);
        }
        return new ByteArrayInputStream(data);
    }

    private static String manifestForEntry(String filePath, String urlPath, String hash) {
        return "{"
            + "\"version\":\"v1\","
            + "\"cordovaCompatibilityVersions\":{\"android\":\"android-1\"},"
            + "\"manifest\":[{"
            + "\"where\":\"client\","
            + "\"path\":\"" + filePath + "\","
            + "\"url\":\"" + urlPath + "\","
            + "\"type\":\"js\","
            + "\"cacheable\":true,"
            + "\"hash\":\"" + hash + "\""
            + "}]"
            + "}";
    }
}
