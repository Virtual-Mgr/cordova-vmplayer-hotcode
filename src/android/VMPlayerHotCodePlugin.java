package VMPlayerHotCode;

import android.content.Context;
import android.content.res.AssetManager;
import android.net.Uri;
import android.webkit.WebResourceResponse;
import android.webkit.MimeTypeMap;

import org.apache.cordova.BuildConfig;
import org.apache.cordova.CordovaInterface;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CallbackContext;

import org.apache.cordova.CordovaPluginPathHandler;
import org.apache.cordova.CordovaWebView;
import org.apache.cordova.LOG;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import androidx.webkit.WebViewAssetLoader;

import java.io.BufferedWriter;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.BufferedReader;
import java.io.OutputStreamWriter;
import java.util.ArrayList;
import java.util.Iterator;

// This plugin is used to serve read/write content from the DataFolder or a subfolder of the DataFolder configured by hot-code-config.json
// At startup, if the hot-code-config.json file exists, we read it and serve content from the subfolder specified by the RelativeRoot property.
// If the hot-code-config.json file does not exist, then we copy the contents of the WWW folder to the DataFolder and serve content from there.
public class VMPlayerHotCodePlugin extends CordovaPlugin {
	private static final String LOGTAG = "VMPlayerHotCode";
	private static final String HOT_CODE_CONFIG_JSON = "hot-code-config.json";
	private static final String RELATIVE_ROOT = "relativeRoot";
	private static final String BAKED_FALLBACK = "bakedFallback";

	private class HotCodeConfig {
		public String RelativeRoot;
		public boolean BakedFallback;

		public HotCodeConfig() {

			RelativeRoot = "";
			BakedFallback = true;
		}

		public HotCodeConfig(JSONObject json) throws JSONException {
			this();
			if (json != null) {
				RelativeRoot = json.getString(RELATIVE_ROOT);
				BakedFallback = json.getBoolean(BAKED_FALLBACK);
			}
		}

		public JSONObject toJSON() throws JSONException {
			JSONObject json = new JSONObject();
			json.put(RELATIVE_ROOT, RelativeRoot);
			json.put(BAKED_FALLBACK, BakedFallback);
			return json;
		}
	}

	private class HotCodeFile {
		private String _absoluteRoot;
		private HotCodeConfig _config;

		public HotCodeConfig getConfig() {
			return _config;
		}

		public void cacheAbsoluteRoot() {
			_config = readConfig();
			_absoluteRoot = getSafeAbsoluteRoot();
		}

		public String getSafeAbsoluteRoot() {
			String absoluteRoot = _absoluteRoot;
			if (absoluteRoot == null) {
				absoluteRoot = dataFolderPath();
				HotCodeConfig config = _config;
				if (config == null) {
					config = readConfig();
				}
				if (config != null && config.RelativeRoot != null && config.RelativeRoot.length() > 0) {
					if (config.RelativeRoot.startsWith("/")) {
						absoluteRoot += config.RelativeRoot;
					} else {
						absoluteRoot += "/" + config.RelativeRoot;
					}
				}
			}
			if (!absoluteRoot.endsWith("/")) {
				absoluteRoot += "/";
			}
			return absoluteRoot;
		}

		public HotCodeConfig readConfig() {
			// We look for a file called "hot-code-config.json" in the DataFolder.
			// If it exists, we read it and return the contents.
			// If it doesn't exist, we return null.

			// Get the DataFolder path
			String dataFolderPath = dataFolderPath();

			// Get the hot-code-config.json file
			File configFile = new File(dataFolderPath + "/" + HOT_CODE_CONFIG_JSON);
			if (!configFile.exists()) {
				LOG.i(LOGTAG, HOT_CODE_CONFIG_JSON + " does not exist");
				return new HotCodeConfig();
			}

			// Read the file
			String configJson = null;
			try {
				configJson = readFileContents(configFile);
			} catch (Exception e) {
				LOG.e(LOGTAG, "Error reading " + HOT_CODE_CONFIG_JSON + " : " + e.getMessage(), e);
				return new HotCodeConfig();
			}

			// Parse the JSON
			HotCodeConfig config = null;
			try {
				JSONObject configObject = new JSONObject(configJson);
				config = new HotCodeConfig(configObject);
				return config;
			} catch (Exception e) {
				LOG.e(LOGTAG, "Error parsing " + HOT_CODE_CONFIG_JSON + " : " + e.getMessage(), e);
				return new HotCodeConfig();
			}
		}

		public void writeConfig(HotCodeConfig config) throws JSONException, IOException {
			if (config == null) {
				config = new HotCodeConfig();
			}
			_config = config;

			// Write the config to the file
			File configFile = new File(dataFolderPath() + "/" + HOT_CODE_CONFIG_JSON);
			writeFileContents(configFile, config.toJSON().toString());

			cacheAbsoluteRoot();
		}
	}

	private HotCodeFile _hotCodeFile;
	private JSONObject _spaConfig;

	@Override
	public void initialize(CordovaInterface cordova, CordovaWebView webView) {
		super.initialize(cordova, webView);

		LOG.i(LOGTAG, LOGTAG + " is initializing...");

		// Revert to release code if we don't have a hot-code-config.json file
		_hotCodeFile = new HotCodeFile();
		_hotCodeFile.cacheAbsoluteRoot();

		// Make sure the "files" folder exists and it must be a directory -
		File filesFolder = new File(dataFolderPath() + "/files");
		if (filesFolder.exists() && !filesFolder.isDirectory()) {
			filesFolder.delete();
		}
		if (!filesFolder.exists()) {
			filesFolder.mkdirs();
		}
	}

	public String dataFolderPath() {
		return cordova.getActivity().getApplicationContext().getFilesDir().getAbsolutePath();
	}

	public static String readFileContents(final File file) throws IOException {
		final InputStream inputStream = new FileInputStream(file);
		final BufferedReader reader = new BufferedReader(new InputStreamReader(inputStream));

		final StringBuilder stringBuilder = new StringBuilder();

		boolean done = false;

		while (!done) {
			final String line = reader.readLine();
			done = (line == null);

			if (line != null) {
				stringBuilder.append(line);
			}
		}

		reader.close();
		inputStream.close();

		return stringBuilder.toString();
	}

	public static void writeFileContents(final File file, final String contents) throws IOException {
		final OutputStream outputStream = new FileOutputStream(file);
		final BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(outputStream));

		writer.write(contents);

		writer.close();
		outputStream.close();
	}

	/*
	 * public static void copyAssetFolder(Context context, String sourcePath, String
	 * targetPath) throws IOException {
	 * AssetManager assetManager = context.getAssets();
	 * String[] files = assetManager.list(sourcePath);
	 * 
	 * if (files.length == 0) {
	 * // It's a file, not a directory
	 * copyAssetFile(context, sourcePath, targetPath);
	 * } else {
	 * // It's a directory
	 * File targetDir = new File(targetPath);
	 * if (!targetDir.exists() && !targetDir.mkdirs()) {
	 * throw new IOException("Failed to create directory: " + targetPath);
	 * }
	 * 
	 * for (String file : files) {
	 * copyAssetFolder(context, sourcePath + "/" + file, targetPath + "/" + file);
	 * }
	 * }
	 * }
	 * 
	 * public static void copyAssetFile(Context context, String sourcePath, String
	 * targetPath) throws IOException {
	 * InputStream in = context.getAssets().open(sourcePath);
	 * OutputStream out = new FileOutputStream(targetPath);
	 * byte[] buffer = new byte[1024];
	 * int read;
	 * 
	 * try {
	 * while ((read = in.read(buffer)) != -1) {
	 * out.write(buffer, 0, read);
	 * }
	 * } finally {
	 * in.close();
	 * out.flush();
	 * out.close();
	 * }
	 * }
	 */

	private void deleteRecursive(File fileOrDirectory, boolean includeRoot, String rootPath,
			ArrayList<String> keepPaths) {
		String relativePath = fileOrDirectory.getPath().substring(rootPath.length());
		if (fileOrDirectory.isDirectory())
			for (File child : fileOrDirectory.listFiles())
				deleteRecursive(child, true, rootPath, keepPaths);

		if (includeRoot) {
			Boolean deletePath = true;
			if (keepPaths != null) {
				for (String keepPath : keepPaths) {
					if (keepPath.endsWith("/")) {
						if (fileOrDirectory.isDirectory()) {
							relativePath = relativePath + "/";
						}
						if (relativePath.startsWith(keepPath)) {
							deletePath = false;
						}
					} else if (keepPath.equals(relativePath)) {
						deletePath = false;
					}
				}
			}
			if (deletePath) {
				fileOrDirectory.delete();
			}
		}
	}

	@Override
	public CordovaPluginPathHandler getPathHandler() {
		AssetManager assetManager = this.cordova.getContext().getAssets();
		return new CordovaPluginPathHandler(new WebViewAssetLoader.PathHandler() {
			@Override
			public WebResourceResponse handle(String path) {
				// Handle spa Config
				if (_spaConfig != null) {
					Iterator<String> prefixes = _spaConfig.keys();
					while (prefixes.hasNext()) {
						String prefix = prefixes.next().toString();
						if (path.startsWith(prefix) || path == prefix) {
							path = _spaConfig.optString(prefix);
						}
					}
				}

				InputStream inputStream = null;
				String absoluteRoot = _hotCodeFile.getSafeAbsoluteRoot();
				File file = new File(absoluteRoot + path);
				if (!file.exists()) {
					if (_hotCodeFile.getConfig().BakedFallback) {
						if (path.isEmpty()) {
							path = "index.html";
						}

						try {
							inputStream = assetManager.open("www/" + path,
									AssetManager.ACCESS_STREAMING);
						} catch (IOException e) {
							return new WebResourceResponse("text/plain", "UTF-8", 404, "Not found", null, null);
						}
					} else {
						return new WebResourceResponse("text/plain", "UTF-8", 404, "Not found", null, null);
					}
				} else {
					try {
						inputStream = new FileInputStream(file);
					} catch (FileNotFoundException e) {
						// This should never happen as we already checked for .exists() above
						return new WebResourceResponse("text/plain", "UTF-8", 404, "Not found", null, null);
					}
				}
				String mimeType = "text/html";
				String extension = MimeTypeMap.getFileExtensionFromUrl(path);
				if (extension != null) {
					if (path.endsWith(".js") || path.endsWith(".mjs")) {
						// Make sure JS files get the proper mimetype to support ES modules
						mimeType = "application/javascript";
					} else if (path.endsWith(".wasm")) {
						mimeType = "application/wasm";
					} else {
						mimeType = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension);
					}
				}

				return new WebResourceResponse(mimeType, null, inputStream);
			}
		});
	}

	private boolean setSpaConfig(JSONArray args, CallbackContext callbackContext) {
		JSONObject config = args.optJSONObject(0);
		_spaConfig = config;

		callbackContext.success();

		return true;
	}

	private void revertToReleaseCode(JSONArray args, CallbackContext callbackContext) {
		try {
			ArrayList<String> keepPaths = null;
			if (args != null) {
				if (args.length() > 0) {
					JSONObject options = args.getJSONObject(0);
					JSONArray keep = options.optJSONArray("keep");
					if (keep != null) {
						keepPaths = new ArrayList<>();
						for (int i = 0; i < keep.length(); i++) {
							keepPaths.add(keep.getString(i));
						}
					}
				}
			}
			// For our Android app, we need to delete the entire contents of the DataFolder
			// and then copy the readonly WWW folder to the DataFolder.
			// Get the DataFolder path
			String dataFolderPath = dataFolderPath();
			LOG.i(LOGTAG, "DataFolder path: " + dataFolderPath);

			// If it exists, delete it
			File dataFolder = new File(dataFolderPath);
			if (dataFolder.exists()) {
				LOG.i(LOGTAG, "DataFolder exists, deleting...");
				deleteRecursive(dataFolder, false, dataFolderPath, keepPaths);
			}

			/*
			 * // Copy the WWW folder to the DataFolder
			 * LOG.i(LOGTAG, "Copying WWW folder to DataFolder...");
			 * copyAssetFolder(cordova.getActivity().getApplicationContext(), "www",
			 * dataFolderPath);
			 */

			// Return success
			if (callbackContext != null) {
				callbackContext.success();
			}
		} catch (Exception e) {
			// Log the error
			LOG.e(LOGTAG, "Error reverting to release code: " + e.getMessage(), e);

			// Return the error to Cordova
			if (callbackContext != null) {
				callbackContext.error("Error reverting to release code: " + e.getMessage());
			}
		}
	}

	public void getHotCodeConfig(JSONArray args, CallbackContext callbackContext) throws JSONException {
		callbackContext.success(_hotCodeFile.getConfig().toJSON());
	}

	public void setHotCodeConfig(JSONArray args, CallbackContext callbackContext) throws JSONException {
		JSONObject options = null;
		if (args.length() > 0) {
			options = args.getJSONObject(0);

			HotCodeConfig config = new HotCodeConfig(options);
			try {
				_hotCodeFile.writeConfig(config);
				callbackContext.success();
			} catch (Exception e) {
				// Log the error
				LOG.e(LOGTAG, "setHotCodeConfig: " + e.getMessage(), e);

				// Return the error to Cordova
				if (callbackContext != null) {
					callbackContext.error("setHotCodeConfig: " + e.getMessage());
				}
			}
		} else {
			callbackContext.error("Missing HotCodeConfig");
		}
	}

	@Override
	public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
		if (action.equals("revertToReleaseCode")) {
			revertToReleaseCode(args, callbackContext);
			return true;
		} else if (action.equals("getHotCodeConfig")) {
			getHotCodeConfig(args, callbackContext);
			return true;
		} else if (action.equals("setHotCodeConfig")) {
			setHotCodeConfig(args, callbackContext);
			return true;
		} else if (action.equals("setSpaConfig")) {
			return setSpaConfig(args, callbackContext);
		}

		return false;
	}

}
