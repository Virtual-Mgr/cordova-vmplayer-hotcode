
#import <Cordova/CDVPlugin.h>
#import "GCDWebServer.h"
#import "GCDWebServerPrivate.h"
#import <Cordova/CDVViewController.h>
#import <Cordova/NSDictionary+CordovaPreferences.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <objc/message.h>
#import <netinet/in.h>

static NSString* const HOT_CODE_CONFIG_JSON = @"hot-code-config.json";
static NSString* const RELATIVE_ROOT = @"relativeRoot";
static NSString* const BAKED_FALLBACK = @"bakedFallback";

// Global function for retrieving the path to the app's Documents folder
NSString* dataFolderPath(void) {
    NSString* path = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    path = [path stringByAppendingPathComponent:@"NoCloud"];
    return path;
}


@interface GCDWebServer()
- (GCDWebServerResponse*)_responseWithContentsOfDirectory:(NSString*)path;
@end

@interface HotCodeConfig : NSObject
@property (nonatomic, strong) NSString *RelativeRoot;
@property (nonatomic) BOOL BakedFallback;

-(id)initWithDictionary:(NSDictionary *)dictionary;
-(NSDictionary *)toJSON;
@end

@interface HotCodeFile : NSObject
@property (nonatomic, strong) NSString *AbsoluteRoot;
@property (nonatomic, strong) HotCodeConfig *Config;
-(void)cacheAbsoluteRoot;
-(NSString *)getSafeAbsoluteRoot;
-(HotCodeConfig *)readConfig;
-(void)writeConfig:(HotCodeConfig *)config;
@end


@implementation HotCodeConfig 
@synthesize RelativeRoot, BakedFallback;

-(id)init
{
    RelativeRoot = @"";
    BakedFallback = YES;
    return self;
}

-(id)initWithDictionary:(NSDictionary *)dictionary
{
    self = [self init];
    
    if (dictionary != nil) {
        RelativeRoot = [dictionary objectForKey:RELATIVE_ROOT];
        if (RelativeRoot == nil || [NSNull isEqual:RelativeRoot]) {
            RelativeRoot = @"";
        }
        
        NSNumber* bakedFallback = [dictionary objectForKey:BAKED_FALLBACK];
        if (bakedFallback != nil && ![NSNull isEqual:bakedFallback]) {
            BakedFallback = [bakedFallback boolValue];
        }
    }

    return self;
}

-(NSDictionary *)toJSON
{
    return @{
        RELATIVE_ROOT: RelativeRoot,
        BAKED_FALLBACK: [NSNumber numberWithBool: BakedFallback]
    };
}
@end

@implementation HotCodeFile 
NSString *_dataFolderPath;
@synthesize AbsoluteRoot, Config;

-(id)init
{
    AbsoluteRoot = nil;
    Config = nil;
    _dataFolderPath = dataFolderPath();
    return self;
}

-(void)cacheAbsoluteRoot
{
    Config = [self readConfig];
    AbsoluteRoot = [self getSafeAbsoluteRoot];
}

-(NSString *)getSafeAbsoluteRoot
{
    NSString *absoluteRoot = AbsoluteRoot;
    if (absoluteRoot == nil) {
        absoluteRoot = _dataFolderPath;
        HotCodeConfig *config = Config;
        if (config == nil) {
            config = [self readConfig];
        }
        if (config != nil && config.RelativeRoot != nil && config.RelativeRoot.length > 0) {
            if (![config.RelativeRoot hasPrefix:@"/"]) {
                absoluteRoot = [absoluteRoot stringByAppendingString:@"/"];
            }
            absoluteRoot = [absoluteRoot stringByAppendingString:config.RelativeRoot];
        }
    }

    if (![absoluteRoot hasSuffix:@"/"]) {
        absoluteRoot = [absoluteRoot stringByAppendingString:@"/"];
    }
    return absoluteRoot;
}

-(HotCodeConfig *)readConfig
{
    NSString *configFilePath = [_dataFolderPath stringByAppendingString:@"/"];
    configFilePath = [configFilePath stringByAppendingString:HOT_CODE_CONFIG_JSON];
    if (![[NSFileManager defaultManager] fileExistsAtPath:configFilePath]) {
        return [[HotCodeConfig alloc] init];
    }

    NSString *configJson = [NSString stringWithContentsOfFile:configFilePath encoding:NSUTF8StringEncoding error:nil];
    if (configJson == nil) {
        return [[HotCodeConfig alloc] init];
    }

    NSError *error = nil;
    NSDictionary *configDictionary = [NSJSONSerialization JSONObjectWithData:[configJson dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&error];
    if (error != nil) {
        return [[HotCodeConfig alloc] init];
    }

    return [[HotCodeConfig alloc] initWithDictionary:configDictionary];
}

-(void)writeConfig:(HotCodeConfig *)config
{
    if (config == nil) {
        config = [[HotCodeConfig alloc] init];
    }
    Config = config;

    // Write the config to the file
    NSString *configFilePath = [_dataFolderPath stringByAppendingString:@"/"];
    configFilePath = [configFilePath stringByAppendingString:HOT_CODE_CONFIG_JSON];
    NSError *error = nil;
    NSData *configData = [NSJSONSerialization dataWithJSONObject:[config toJSON] options:0 error:&error];
    if (error != nil) {
        return;
    }
    [configData writeToFile:configFilePath atomically:YES];

    [self cacheAbsoluteRoot];
}

@end

@interface VMPlayerHotCodePlugin : CDVPlugin

@property(nonatomic, strong) GCDWebServer *server;

@end


@implementation VMPlayerHotCodePlugin

NSString* _dataFolderPath;
NSString* _httpURL;
HotCodeFile *_hotCodeFile;
NSDictionary *_spaConfig;

-(void)pluginInitialize
{
    CDVViewController *vc = (CDVViewController *)self.viewController;

    NSUInteger port = 0;
    NSString* indexPage = vc.startPage;

    _dataFolderPath = dataFolderPath();
    _hotCodeFile = [[HotCodeFile alloc] init];
    [_hotCodeFile cacheAbsoluteRoot];
    
    // The authToken is appended to index.html as a query parameter and when this page loads will be pushed into a Cookie
    // this prevents other iOS Apps from hitting our Http server without the random token
    NSString* authToken = [NSString stringWithFormat:@"cdvToken=%@", [[NSProcessInfo processInfo] globallyUniqueString]];

    self.server = [[GCDWebServer alloc] init];
    [GCDWebServer setLogLevel:kGCDWebServerLoggingLevel_Error];

    // add after server is started to get the true port
    [self addHotCodeFileSystemHandler:authToken];

    // handlers must be added before server starts
    NSMutableDictionary* options = [[NSMutableDictionary alloc] init];
    [options setValue:[NSNumber numberWithUnsignedShort:port] forKey:GCDWebServerOption_Port];
    [options setValue:[NSNumber numberWithBool:YES] forKey:GCDWebServerOption_BindToLocalhost];
    NSError* error = nil;
    if (![self.server startWithOptions:options error:&error])
    {
        NSLog(@"Could not start GCDWebServer !!");
    }
    else
    {
        _httpURL = [NSString stringWithFormat:@"http://localhost:%lu/", (unsigned long)self.server.port];
        vc.startPage = [NSString stringWithFormat:@"%@%@?%@", _httpURL, indexPage, authToken];
    }
}

/*
-(void)copyAssetFolder:(NSString *)sourcePath targetPath:(NSString *)targetPath
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    
    // Ensure the target directory exists
    if (![fileManager fileExistsAtPath:targetPath]) {
        [fileManager createDirectoryAtPath:targetPath withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            NSLog(@"Error creating directory: %@", error);
            return;
        }
    }
    
    NSArray *files = [fileManager contentsOfDirectoryAtPath:sourcePath error:&error];
    if (error != nil) {
        NSLog(@"Error getting contents of directory: %@", error);
        return;
    }

    for (NSString *file in files) {
        NSString *sourceFilePath = [sourcePath stringByAppendingPathComponent:file];
        NSString *targetFilePath = [targetPath stringByAppendingPathComponent:file];
        BOOL isDirectory = NO;
        BOOL exists = [fileManager fileExistsAtPath:sourceFilePath isDirectory:&isDirectory];
        if (!exists) {
            NSLog(@"File does not exist: %@", sourceFilePath);
            continue;
        }

        if (isDirectory) {
            [self copyAssetFolder:sourceFilePath targetPath:targetFilePath];
        } else {
            [self copyAssetFile:sourceFilePath targetPath:targetFilePath];
        }
    }
}

-(void)copyAssetFile:(NSString *)sourcePath targetPath:(NSString *)targetPath
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:targetPath]) {
        [fileManager removeItemAtPath:targetPath error:nil];
    }

    [fileManager copyItemAtPath:sourcePath toPath:targetPath error:nil];
}
*/
-(void)deleteRecursive:(NSString *)path includeRoot:(BOOL)includeRoot rootPath:(NSString*)rootPath keepPaths:(NSArray*)keepPaths
{
    NSString* relativePath = [path substringFromIndex:[rootPath length]];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    BOOL exists = [fileManager fileExistsAtPath:path isDirectory:&isDirectory];
    if (!exists) {
        return;
    }

    if (isDirectory) {
        NSArray *files = [fileManager contentsOfDirectoryAtPath:path error:nil];
        for (NSString *file in files) {
            NSString *childPath = [path stringByAppendingPathComponent:file];
            [self deleteRecursive:childPath includeRoot:YES rootPath:rootPath keepPaths:keepPaths];
        }
    }

    if (includeRoot) {
        BOOL deletePath = YES;
        if (keepPaths != nil) {
            for (NSString* keepPath in keepPaths) {
                if ([keepPath hasSuffix:@"/"]) {
                    if (isDirectory) {
                        relativePath = [relativePath stringByAppendingString:@"/"];
                    }
                    if ([relativePath hasPrefix:keepPath]) {
                        deletePath = NO;
                    }
                } else if ([keepPath isEqual:relativePath]) {
                    deletePath = NO;
                }
            }
        }
        
        if (deletePath) {
            [fileManager removeItemAtPath:path error:nil];
        }
    }
}

-(void)setSpaConfig:(CDVInvokedUrlCommand *)command
{
    CDVPluginResult *pluginResult = nil;
    if (command.arguments.count == 0) {
        // Invalid argument count
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Invalid argument count"];
    }

    if (pluginResult == nil) {
        _spaConfig = [command.arguments objectAtIndex:0];
        if ([NSNull isEqual:_spaConfig]) {
            _spaConfig = nil;
        }
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

-(void)revertToReleaseCode:(CDVInvokedUrlCommand *)command
{
    @try {
        NSArray* keepPaths = nil;
        
        if (command != nil) {
            if (command.arguments.count > 0) {
                NSDictionary* options = [command.arguments objectAtIndex:0];
                keepPaths = [options objectForKey:@"keep"];
            }
        }
        
        // For our app, we need to delete the entire contents of the DataFolder
        // and then copy the readonly WWW folder to the DataFolder.
        // Get the DataFolder path
        NSString *folderPath = dataFolderPath();
        NSLog(@"DataFolder path: %@", folderPath);

        // If it exists, delete it
        NSFileManager *fileManager = [NSFileManager defaultManager];
        BOOL isDirectory = NO;
        BOOL exists = [fileManager fileExistsAtPath:folderPath isDirectory:&isDirectory];
        if (exists) {
            NSLog(@"DataFolder exists, deleting...");
            [self deleteRecursive:folderPath includeRoot:NO rootPath:folderPath keepPaths:keepPaths];
        }

/*
        // Copy the WWW folder to the DataFolder
        NSLog(@"Copying WWW folder to DataFolder...");
        NSString* wwwAssetFolder = [[[NSBundle mainBundle] resourcePath] stringByAppendingString:@"/www"];
        [self copyAssetFolder:wwwAssetFolder targetPath:folderPath];
*/
        // Return success
        if (command != nil) {
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    }
    @catch (NSException *exception) {
        // Log the error
        NSLog(@"Error reverting to release code: %@", exception);

        // Return the error to Cordova
        if (command != nil) {
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"Error reverting to release code: %@", exception]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    }
}

-(void)getHotCodeConfig:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:[_hotCodeFile.Config toJSON]];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

-(void)setHotCodeConfig:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    
    NSDictionary* options = nil;
    if (command.arguments.count > 0) {
        options = [command.arguments objectAtIndex:0];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Missing HotCodeConfig"];
    }
    
    if (pluginResult == nil) {
        [_hotCodeFile writeConfig:[[HotCodeConfig alloc] initWithDictionary:options]];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

-(void)getHttpURL:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:_httpURL];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (NSUInteger) _availablePort
{
    struct sockaddr_in addr4;
    bzero(&addr4, sizeof(addr4));
    addr4.sin_len = sizeof(addr4);
    addr4.sin_family = AF_INET;
    addr4.sin_port = 0; // set to 0 and bind to find available port
    addr4.sin_addr.s_addr = htonl(INADDR_ANY);

    int listeningSocket = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (bind(listeningSocket, (const void*)&addr4, sizeof(addr4)) == 0) {
        struct sockaddr addr;
        socklen_t addrlen = sizeof(addr);
        if (getsockname(listeningSocket, &addr, &addrlen) == 0) {
            struct sockaddr_in* sockaddr = (struct sockaddr_in*)&addr;
            close(listeningSocket);
            return ntohs(sockaddr->sin_port);
        }
    }
    
    return 0;
}

- (void) addHotCodeFileSystemHandler:(NSString*)authToken
{
    NSString* basePath = @"/";
    BOOL allowRangeRequests = YES;
    NSString* wwwPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"www"];

    GCDWebServerAsyncProcessBlock processRequestBlock = ^void (GCDWebServerRequest* request, GCDWebServerCompletionBlock complete) {
        NSString* folderPath = [_hotCodeFile AbsoluteRoot];
        NSString* path = [request.path substringFromIndex:basePath.length];
        NSString* originalPath = path;
        NSString* mappedPath = nil;
        if (_spaConfig != nil) {
            for (NSString* prefix in _spaConfig) {
                if ([path hasPrefix:prefix] || [path isEqualToString:prefix]) {
                    mappedPath = [_spaConfig objectForKey:prefix];
                }
            }
        }
    
        if (mappedPath != nil) {
            path = mappedPath;
        }

        NSString* servedFrom = @"data ";
        NSString* filePath = [folderPath stringByAppendingPathComponent:path];
        NSString* fileType = [[[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:NULL] fileType];
        GCDWebServerResponse* response = nil;

        if (fileType == nil && _hotCodeFile.Config.BakedFallback) {
            servedFrom = @"baked";
            filePath = [wwwPath stringByAppendingPathComponent:path];
            fileType = [[[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:NULL] fileType];
        }
        
        if (fileType && [fileType isEqualToString:NSFileTypeRegular]) {
            if (allowRangeRequests) {
                response = [GCDWebServerFileResponse responseWithFile:filePath byteRange:request.byteRange];
                [response setValue:@"bytes" forAdditionalHeader:@"Accept-Ranges"];
            } else {
                response = [GCDWebServerFileResponse responseWithFile:filePath];
            }
            
            // Don't use LastModifiedDate - the GCDWebServer has a bug where it compares last-modified before eTag which is wrong, because of this
            // files baked today are treated as cached even if there is an updated (downloaded bundle) in the data folder
            // Anyway, we cant trust LastModifiedDate
            response.lastModifiedDate = nil;
        }

        if (response != nil) {
            if (mappedPath != nil) {
                NSLog(@"Mapping %@:'%@' to '%@'", servedFrom, originalPath, mappedPath);
            } else {
                NSLog(@"Serving %@:'%@'", servedFrom, path);
            }
        } else {
            NSLog(@"Not found '%@'", path);
        }
        complete(response);
    };

    [self addFileSystemHandler:processRequestBlock basePath:basePath authToken:authToken cacheAge:0];
}

- (void) addFileSystemHandler:(GCDWebServerAsyncProcessBlock)processRequestForResponseBlock basePath:(NSString*)basePath authToken:(NSString*)authToken cacheAge:(NSUInteger)cacheAge
{
    GCDWebServerMatchBlock matchBlock = ^GCDWebServerRequest *(NSString* requestMethod, NSURL* requestURL, NSDictionary* requestHeaders, NSString* urlPath, NSDictionary* urlQuery) {

        if (![requestMethod isEqualToString:@"GET"]) {
            return nil;
        }
        if (![urlPath hasPrefix:basePath]) {
            return nil;
        }
        return [[GCDWebServerRequest alloc] initWithMethod:requestMethod url:requestURL headers:requestHeaders path:urlPath query:urlQuery];
    };

    GCDWebServerAsyncProcessBlock asyncProcessBlock = ^void (GCDWebServerRequest* request, GCDWebServerCompletionBlock complete) {

        //check if it is a request from localhost
        NSString *host = [request.headers objectForKey:@"Host"];
        if (host==nil || [host hasPrefix:@"localhost"] == NO ) {
            complete([GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"FORBIDDEN"]);
            return;
        }

        //check if the querystring or the cookie has the token
        BOOL hasToken = (request.URL.query && [request.URL.query containsString:authToken]);
        NSString *cookie = [request.headers objectForKey:@"Cookie"];
        BOOL hasCookie = (cookie && [cookie containsString:authToken]);
        if (!hasToken && !hasCookie) {
            complete([GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"FORBIDDEN"]);
            return;
        }

        processRequestForResponseBlock(request, ^void(GCDWebServerResponse* response){
            if (response) {
                response.cacheControlMaxAge = cacheAge;
            } else {
                response = [GCDWebServerResponse responseWithStatusCode:kGCDWebServerHTTPStatusCode_NotFound];
            }

            if (hasToken && !hasCookie) {
                //set cookie
                [response setValue:[NSString stringWithFormat:@"%@;path=/", authToken] forAdditionalHeader:@"Set-Cookie"];
            }
            complete(response);
        });
    };

    [self.server addHandlerWithMatchBlock:matchBlock asyncProcessBlock:asyncProcessBlock];
}

@end
