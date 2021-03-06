//
//  SHKOneNote.m
//
//  Copyright (c) Microsoft Corporation
//  All rights reserved.
//
//  MIT License:
//
//  Permission is hereby granted, free of charge, to any person obtaining
//  a copy of this software and associated documentation files (the
//  ""Software""), to deal in the Software without restriction, including
//  without limitation the rights to use, copy, modify, merge, publish,
//  distribute, sublicense, and/or sell copies of the Software, and to
//  permit persons to whom the Software is furnished to do so, subject to
//  the following conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED ""AS IS"", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
//  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
//  LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
//  OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
//  WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


#import "SHKOneNote.h"
#import "SHKConfiguration.h"
#import "SHK.h"
#import "LiveSDK/LiveConnectClient.h"
#import "AFURLRequestSerialization.h"
#import "ISO8601DateFormatter.h"
#import "SHKFormFieldSettings.h"
#import "SHKFormFieldLargeTextSettings.h"
#import "SHKRequest.h"
#import "SHKOneNoteRequest.h"
#import "SHKSharer_protected.h"

static NSString * const OneNoteHost = @"https://www.onenote.com/api/v1.0/pages";

@interface OneNoteController : NSObject <LiveAuthDelegate>
    @property(strong, nonatomic) SHKOneNote *owner;
@end

@implementation OneNoteController
- (void)authCompleted:(LiveConnectSessionStatus)status
              session:(LiveConnectSession *)session
            userState:(id)userState {
    if ([userState isEqual:@"signin"]) {
        if (session != nil) {
            [self.owner tryPendingAction];
        }
    }
}

- (void)authFailed:(NSError *)error
         userState:(id)userState {
    [[[UIAlertView alloc] initWithTitle:SHKLocalizedString(@"Authorize Error")
                                message:SHKLocalizedString(@"There was an error while authorizing")
                               delegate:nil
                      cancelButtonTitle:SHKLocalizedString(@"Close")
                      otherButtonTitles:nil] show];
}

@end

@interface SHKOneNote ()
+ (LiveConnectClient *)sharedClient;

+ (OneNoteController *)sharedController;

- (void)sendText;

- (void)sendImage;

- (void)sendTextAndLink;

- (void)sendFile;

+ (NSString *)getDate;
@end

@implementation SHKOneNote

#pragma mark - Configuration : Service Definition

+ (NSString *)sharerTitle {
    return SHKLocalizedString(@"OneNote");
}

+ (BOOL)canShareURL {
    return YES;
}

+ (BOOL)canShareImage {
    return YES;
}

+ (BOOL)canShareText {
    return YES;
}

+ (BOOL)canShareFile:(SHKFile *)file {
    return YES;  //{ return [file.mimeType hasPrefix:@"image/"]; }
}

+ (BOOL)canShare {
    return YES;
}

+ (BOOL)canShareOffline {
    return NO;
}

+ (BOOL)canAutoShare {
    return YES;
}

+ (LiveConnectClient *)sharedClient {
    static LiveConnectClient *sharedClient;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sharedClient = [[LiveConnectClient alloc] initWithClientId:SHKCONFIG(onenoteClientId) delegate:nil];
    });
    return sharedClient;
}

+ (OneNoteController *)sharedController {
    static OneNoteController *sharedController;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sharedController = [[OneNoteController alloc] init];
    });
    return sharedController;
}


- (id)init {
    if (self = [super init]) {
        OneNoteController *sharedController = [SHKOneNote sharedController];
        sharedController.owner = self;
    }
    return self;
}

#pragma mark -
#pragma mark Authentication

- (BOOL)isAuthorized {
    return [SHKOneNote sharedClient].session.accessToken != nil;
}

- (void)authorizationFormShow {
    [[SHKOneNote sharedClient] login:[SHK currentHelper].rootViewForUIDisplay
                              scopes:[NSArray arrayWithObjects:@"office.onenote_create", @"wl.signin", @"wl.offline_access", nil]
                            delegate: [SHKOneNote sharedController]
                           userState:@"signin"];
}

- (void)logout {
    [SHKOneNote sharedClient].logout;
}

#pragma mark -
#pragma mark Share API Methods

- (BOOL)send {
    if (![self validateItem])
        return NO;

    //[self setQuiet:NO];

    switch (self.item.shareType) {
        case SHKShareTypeURL:
            [self sendTextAndLink];
            break;
        case SHKShareTypeText:
            [self sendText];
            break;
        case SHKShareTypeImage:
            [self sendImage];
            break;
        case SHKShareTypeFile:
            [self sendFile];
            break;
        default:
            return NO;
    }

    [self sendDidStart];
    return YES;
}

- (void)sendText {
    NSString *date = [SHKOneNote getDate];
    NSString *title = self.item.title ? self.item.title : @"Sharing Text via ShareKit";
    NSString *simpleHtml = [NSString stringWithFormat:
            @"<html><head><title>%@</title><meta name=\"created\" content=\"%@\" /></head><body>%@</body></html>",
            title, date, self.item.text];
    NSMutableDictionary *headers = [[NSMutableDictionary alloc] init];
    [headers setValue:@"text/html" forKey:@"Content-Type"];

    if ([SHKOneNote sharedClient].session) {
        [headers setValue:[@"Bearer " stringByAppendingString:[SHKOneNote sharedClient].session.accessToken] forKey:@"Authorization"];
    }

    SHKRequest *request = [[SHKRequest alloc] initWithURL:[[NSURL alloc] initWithString:OneNoteHost]
                                                   params:simpleHtml
                                                   method:@"POST"
                                               completion:^(SHKRequest *request) {
                                                   if (request.success) {
                                                       [self sendDidFinish];
                                                   } else {
                                                       [self sendDidFailWithError:[SHK error:SHKLocalizedString(@"There was a problem sharing with OneNote")]];
                                                   }
                                               }];

    request.headerFields = headers;
    [request start];

}

- (void)sendImage {
    NSString *date = [SHKOneNote getDate];
    NSString *title = self.item.title ? self.item.title : @"Sharing an Image via ShareKit";

    NSString *simpleHtml = [NSString stringWithFormat:
            @"<html><head><title>%@</title><meta name=\"created\" content=\"%@\" /></head><body>"
                    "<img src=\"name:image1\" width=\"%.0f\" height=\"%.0f\" />"
                    "</body></html>",
            title, date, self.item.image.size.width, self.item.image.size.height];
    NSData *image1 = UIImageJPEGRepresentation(self.item.image, 1.0);
    NSData *presentation = [simpleHtml dataUsingEncoding:NSUTF8StringEncoding];

    NSMutableURLRequest *multipartrequest = [[AFHTTPRequestSerializer serializer] multipartFormRequestWithMethod:@"POST"
                                                                                              URLString:OneNoteHost
                                                                                             parameters:nil
                                                                              constructingBodyWithBlock:^(id <AFMultipartFormData> formData) {
                                                                                  [formData
                                                                                          appendPartWithHeaders:@{
                                                                                                  @"Content-Disposition" : @"form-data; name=\"Presentation\"",
                                                                                                  @"Content-Type" : @"text/html"}
                                                                                                           body:presentation];
                                                                                  [formData
                                                                                          appendPartWithHeaders:@{
                                                                                                  @"Content-Disposition" : @"form-data; name=\"image1\"",
                                                                                                  @"Content-Type" : @"image/jpeg"}
                                                                                                           body:image1];
                                                                              }];

    if ([SHKOneNote sharedClient].session) {
        [multipartrequest setValue:[@"Bearer " stringByAppendingString:[SHKOneNote sharedClient].session.accessToken] forHTTPHeaderField:@"Authorization"];
    }
    SHKOneNoteRequest *request = [[SHKOneNoteRequest alloc] initWithRequest:multipartrequest
                                                                 completion:^(SHKRequest *request) {
                                                                     if (request.success) {
                                                                         [self sendDidFinish];
                                                                     } else {
                                                                         [self sendDidFailWithError:[SHK error:SHKLocalizedString(@"There was a problem sharing with OneNote")]];
                                                                     }
                                                                 }];

    request.headerFields = [multipartrequest allHTTPHeaderFields];
    [request start];
}

- (void)sendTextAndLink {
    NSString *date = [SHKOneNote getDate];
    NSString *title = self.item.title ? self.item.title : @"Sharing a Link via ShareKit";
    NSString *strURL = [self.item.URL absoluteString];
    NSString *simpleHtml = [NSString stringWithFormat:@"<html><head><title>%@</title><meta name=\"created\" content=\"%@\" /></head><body>", title, date];
    simpleHtml = [simpleHtml stringByAppendingFormat:
            @"<p><div>%@</div><br/><a href=\"%@\">%@</a></p> <img data-render-src=\"%@\"/></body></html>",
                    self.item.text, strURL, strURL, strURL];
    simpleHtml = [simpleHtml stringByAppendingString:@"</body></html>"];

    NSData *presentation = [simpleHtml dataUsingEncoding:NSUTF8StringEncoding];

    NSMutableURLRequest *multipartrequest = [[AFHTTPRequestSerializer serializer] multipartFormRequestWithMethod:@"POST" URLString:OneNoteHost parameters:nil constructingBodyWithBlock:^(id <AFMultipartFormData> formData) {
        [formData
                appendPartWithHeaders:@{
                        @"Content-Disposition" : @"form-data; name=\"Presentation\"",
                        @"Content-Type" : @"text/html"}
                                 body:presentation];
        if (self.item.image) {
            NSData *image1 = UIImageJPEGRepresentation(self.item.image, 1.0);
            [formData
                    appendPartWithHeaders:@{
                            @"Content-Disposition" : @"form-data; name=\"image1\"",
                            @"Content-Type" : @"image/jpeg"}
                                     body:image1];

        }
    }];

    if ([SHKOneNote sharedClient].session) {
        [multipartrequest setValue:[@"Bearer " stringByAppendingString:[SHKOneNote sharedClient].session.accessToken] forHTTPHeaderField:@"Authorization"];
    }

    SHKOneNoteRequest *request = [[SHKOneNoteRequest alloc] initWithRequest:multipartrequest
                                                                 completion:^(SHKRequest *request) {
                                                                     if (request.success) {
                                                                         [self sendDidFinish];
                                                                     } else {
                                                                         [self sendDidFailWithError:[SHK error:SHKLocalizedString(@"There was a problem sharing with OneNote")]];
                                                                     }
                                                                 }];

    request.headerFields = [multipartrequest allHTTPHeaderFields];
    [request start];
}

- (void)sendFile {
    NSString *date = [SHKOneNote getDate];
    NSString *title = self.item.title ? self.item.title : @"Sharing a File via ShareKit";
    NSString *simpleHtml = [NSString stringWithFormat:
            @"<html><head><title>%@</title><meta name=\"created\" content=\"%@\" /></head><body>",
            title, date];

    NSString *mime = self.item.file.mimeType;
    NSData *embedded1 = [NSData dataWithContentsOfFile:self.item.file.path];
    simpleHtml = [simpleHtml stringByAppendingFormat:
            @"<object data-attachment=\"%@\" data=\"name:embedded1\" type=\"%@\" />",
            self.item.file.path.lastPathComponent, mime];


    simpleHtml = [simpleHtml stringByAppendingString:@"</body></html>"];
    NSData *presentation = [simpleHtml dataUsingEncoding:NSUTF8StringEncoding];

    NSMutableURLRequest *multipartrequest = [
            [AFHTTPRequestSerializer serializer]
            multipartFormRequestWithMethod:@"POST" URLString:OneNoteHost parameters:nil constructingBodyWithBlock:^(id <AFMultipartFormData> formData) {
                [formData appendPartWithHeaders:@{
                        @"Content-Disposition" : @"form-data; name=\"Presentation\"",
                        @"Content-Type" : @"text/html"}
                                           body:presentation];
                [formData appendPartWithHeaders:@{
                        @"Content-Disposition" : @"form-data; name=\"embedded1\"",
                        @"Content-Type" : mime}
                                           body:embedded1];

            }];
    if ([SHKOneNote sharedClient].session) {
        [multipartrequest setValue:[@"Bearer " stringByAppendingString:[SHKOneNote sharedClient].session.accessToken] forHTTPHeaderField:@"Authorization"];
    }
    SHKOneNoteRequest *request = [[SHKOneNoteRequest alloc] initWithRequest:multipartrequest
                                                                 completion:^(SHKRequest *request) {
                                                                     if (request.success) {
                                                                         [self sendDidFinish];
                                                                     } else {
                                                                         [self sendDidFailWithError:[SHK error:SHKLocalizedString(@"There was a problem sharing with OneNote")]];
                                                                     }
                                                                 }];

    request.headerFields = [multipartrequest allHTTPHeaderFields];
    [request start];
}

//- (NSString *)enMediaTagWithResource:(SHKFile *)file width:(CGFloat)width height:(CGFloat)height {
//    NSString *sizeAtr = width > 0 && height > 0 ? [NSString stringWithFormat:@"height=\"%.0f\" width=\"%.0f\" ",height,width]:@"";
//    return [NSString stringWithFormat:@"<en-media type=\"%@\" %@hash=\"%@\"/>",src.mime,sizeAtr,[src.data.body md5]];
//}

#pragma mark -
#pragma mark Share Form

- (NSArray *)shareFormFieldsForType:(SHKShareType)type {
    NSString *text;
    NSString *key;
    BOOL allowEmptyMessage = NO;

    switch (self.item.shareType) {
        case SHKShareTypeText:
            text = self.item.text;
            key = @"text";
            break;
        case SHKShareTypeImage:
            text = self.item.title;
            key = @"title";
            allowEmptyMessage = YES;
            break;
        case SHKShareTypeURL:
            text = self.item.text;
            key = @"text";
            allowEmptyMessage = YES;
            break;
        case SHKShareTypeFile:
            text = self.item.text;
            key = @"text";
            break;
        default:
            return nil;
    }

    SHKFormFieldLargeTextSettings *commentField = [SHKFormFieldLargeTextSettings label:SHKLocalizedString(@"Comment")
                                                                                   key:key
                                                                                 start:text
                                                                                  item:self.item];
    commentField.select = YES;
    commentField.validationBlock = ^(SHKFormFieldLargeTextSettings *formFieldSettings) {
        BOOL result;
        if (allowEmptyMessage) {
            result = YES;
        } else {
            result = [formFieldSettings.valueToSave length] > 0;
        }
        return result;
    };

    NSMutableArray *result = [@[commentField] mutableCopy];

    if (self.item.shareType == SHKShareTypeURL || self.item.shareType == SHKShareTypeFile) {
        SHKFormFieldSettings *title = [SHKFormFieldSettings label:SHKLocalizedString(@"Title") key:@"title" type:SHKFormFieldTypeText start:self.item.title];
        [result insertObject:title atIndex:0];
    }
    return result;
}

#pragma mark -
#pragma mark Helpers
// Get a date in ISO8601 string format
+ (NSString *)getDate {
    ISO8601DateFormatter *isoFormatter = [[ISO8601DateFormatter alloc] init];
    [isoFormatter setDefaultTimeZone:[NSTimeZone localTimeZone]];
    [isoFormatter setIncludeTime:YES];
    NSString *date = [isoFormatter stringFromDate:[NSDate date]];
    return date;
}

@end




