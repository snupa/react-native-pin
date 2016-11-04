//
//  RNNativeFetch.m
//  medipass
//
//  Created by Paul Wong on 13/10/16.
//  Copyright © 2016 Localz. All rights reserved.
//

#import "RNPinch.h"
#import "RCTBridge.h"

@interface NSURLSessionSSLPinningDelegate:NSObject <NSURLSessionDelegate>

- (id)initWithCertName:(NSString *)certName;

@property (nonatomic, strong) NSString *certName;

@end

@implementation NSURLSessionSSLPinningDelegate

- (id)initWithCertName:(NSString *)certName {
    if (self = [super init]) {
        _certName = certName;
    }
    return self;
}

- (NSArray *)pinnedCertificateData {
    NSString *cerPath = [[NSBundle mainBundle] pathForResource:self.certName ofType:@"cer"];
    NSData *localCertData = [NSData dataWithContentsOfFile:cerPath];
    
    NSMutableArray *pinnedCertificates = [NSMutableArray array];
    for (NSData *certificateData in @[localCertData]) {
        [pinnedCertificates addObject:(__bridge_transfer id)SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificateData)];
    }
    return pinnedCertificates;
}

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * _Nullable credential))completionHandler {
    
    if ([[[challenge protectionSpace] authenticationMethod] isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        NSString *domain = challenge.protectionSpace.host;
        SecTrustRef serverTrust = [[challenge protectionSpace] serverTrust];
        
        NSArray *policies = @[(__bridge_transfer id)SecPolicyCreateSSL(true, (__bridge CFStringRef)domain)];
        
        SecTrustSetPolicies(serverTrust, (__bridge CFArrayRef)policies);
        SecTrustSetAnchorCertificates(serverTrust, (__bridge CFArrayRef)self.pinnedCertificateData);
        SecTrustResultType result;
        
        OSStatus errorCode = SecTrustEvaluate(serverTrust, &result);
        
        BOOL evaluatesAsTrusted = (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed);
        if (errorCode == errSecSuccess && evaluatesAsTrusted) {
            NSURLCredential *credential = [NSURLCredential credentialForTrust:serverTrust];
            completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
        } else {
            completionHandler(NSURLSessionAuthChallengeRejectProtectionSpace, NULL);
        }
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, NULL);
    }
}

@end

@interface RNPinch()

@property (nonatomic, strong) NSURLSessionConfiguration *sessionConfig;

@end

@implementation RNPinch
RCT_EXPORT_MODULE();

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        self.sessionConfig.HTTPCookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    }
    return self;
}

RCT_EXPORT_METHOD(fetch:(NSString *)url obj:(NSDictionary *)obj callback:(RCTResponseSenderBlock)callback) {
    NSURL *u = [NSURL URLWithString:url];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:u];
    
    NSURLSession *session;
    if (obj) {
        if (obj[@"method"]) {
            [request setHTTPMethod:[obj[@"method"] lowercaseString]];
        }
        if (obj[@"timeoutInterval"]) {
            request.timeoutInterval = [obj[@"timeoutInterval"] doubleValue];
        }
        if (obj[@"headers"] && [obj[@"headers"] isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *m = [obj[@"headers"] mutableCopy];
            for (NSString *key in [m allKeys]) {
                if (![m[key] isKindOfClass:[NSString class]]) {
                    m[key] = [m[key] stringValue];
                }
            }
            [request setAllHTTPHeaderFields:m];
        }
        if (obj[@"body"]) {
            NSData *data = [obj[@"body"] dataUsingEncoding:NSUTF8StringEncoding];
            [request setHTTPBody:data];
        }
    }
    if (obj && obj[@"sslPinning"] && obj[@"sslPinning"][@"cert"]) {
        NSURLSessionSSLPinningDelegate *delegate = [[NSURLSessionSSLPinningDelegate alloc] initWithCertName:obj[@"sslPinning"][@"cert"]];
        session = [NSURLSession sessionWithConfiguration:self.sessionConfig delegate:delegate delegateQueue:[NSOperationQueue mainQueue]];
    } else {
        session = [NSURLSession sessionWithConfiguration:self.sessionConfig];
    }
    
    __block NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (!error) {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse*) response;
            NSInteger statusCode = httpResp.statusCode;
            NSString *bodyString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            
            NSDictionary *res = @{
                                  @"status": @(statusCode),
                                  @"headers": httpResp.allHeaderFields,
                                  @"bodyString": bodyString
                                  };
            callback(@[[NSNull null], res]);
        } else {
            
            callback(@[@{@"message":error.localizedDescription}, [NSNull null]]);
        }
    }];
    
    [dataTask resume];
}

@end

