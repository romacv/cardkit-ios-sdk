//
//  NSObject+CardKPaymentFlow.m
//  CardKit
//
//  Created by Alex Korotkov on 3/26/21.
//  Copyright © 2021 AnjLab. All rights reserved.
//
#import <PassKit/PassKit.h>
#import "CardKPaymentFlowController.h"
#import "CardKKindPaymentViewController.h"
#import "CardKConfig.h"
#import "RSA.h"
#import "ConfirmChoosedCard.h"
#import "CardKPaymentSessionStatus.h"
#import <ThreeDSSDK/ThreeDSSDK.h>

#import <CardKit/CardKit-Swift.h>
#import "ARes.h"

@implementation CardKPaymentFlowController {
  CardKKindPaymentViewController *_controller;
  NSString *_url;
  UIActivityIndicatorView *_spinner;
  CardKTheme *_theme;
  CardKBinding *_cardKBinding;
  CardKPaymentSessionStatus *_sessionStatus;
  CardKPaymentError *_cardKPaymentError;
  NSString *_seToken;
  TransactionManager *_transactionManager;
}
- (instancetype)init
  {
    self = [super init];
    if (self) {
      _theme = CardKConfig.shared.theme;
      self.view.backgroundColor = CardKConfig.shared.theme.colorTableBackground;
      
      _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
      [self.view addSubview:_spinner];
      _spinner.color = _theme.colorPlaceholder;
      
      _controller = [[CardKKindPaymentViewController alloc] init];
      _controller.cKitDelegate = self;

      [_spinner startAnimating];
      
      _cardKPaymentError = [[CardKPaymentError alloc] init];
      _url = @"https://web.rbsdev.com/soyuzpayment";
      
      _transactionManager = [[TransactionManager alloc] init];
    }
    return self;
  }

  - (void)viewDidLayoutSubviews {
    _spinner.frame = CGRectMake(0, 0, 100, 100);
    _spinner.center = CGPointMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2);
  }

  - (void)viewDidAppear:(BOOL)animated {
    [self _getSessionStatusRequest:^(CardKPaymentSessionStatus * sessionStatus) {
      
    }];
  }
  - (void)viewDidLoad {
    [super viewDidLoad];
  }

  - (NSString *) _urlParameters:(NSArray<NSString *> *) parameters {
    NSString *url = @"";

    for(NSString *parameter in parameters) {
      if ([parameters.lastObject isEqual:parameter]) {
        url = [NSString stringWithFormat:@"%@%@", url, parameter];
      } else {
        url = [NSString stringWithFormat:@"%@%@&", url, parameter];
      }
    }
    
    return url;
  }

  - (void)callPaymentErrorDelegate {
    
  }

  - (void)_sendError {
    self->_cardKPaymentError.massage = @"Ошибка запроса статуса";
    [self->_cardKPaymentFlowDelegate didErrorPaymentFlow:self->_cardKPaymentError];

    dispatch_async(dispatch_get_main_queue(), ^{
      [self.navigationController popViewControllerAnimated:YES];
    });
  }

  - (void)_sendRedirectError {
    self->_cardKPaymentError.massage = self->_sessionStatus.redirect;
    [self->_cardKPaymentFlowDelegate didErrorPaymentFlow: self->_cardKPaymentError];
    
    dispatch_async(dispatch_get_main_queue(), ^{
      [self.navigationController popViewControllerAnimated:YES];
    });
  }
  
  - (void)_moveChoosePaymentMethodController {
    dispatch_async(dispatch_get_main_queue(), ^{
      UIViewController *sourceViewController = self;
      UIViewController *destinationController = self->_controller;
      UINavigationController *navigationController = sourceViewController.navigationController;
      
      [navigationController popToRootViewControllerAnimated:NO];
      [navigationController pushViewController:destinationController animated:NO];
      
      [self->_spinner stopAnimating];
    });
  }

  - (void) _getSessionStatusRequest:(void (^)(CardKPaymentSessionStatus *)) handler {
    NSString *mdOrder = [NSString stringWithFormat:@"%@%@", @"MDORDER=", CardKConfig.shared.mdOrder];
    NSString *URL = [NSString stringWithFormat:@"%@%@?%@", _url, @"/rest/getSessionStatus.do", mdOrder];

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:URL]];

    request.HTTPMethod = @"GET";

    NSURLSession *session = [NSURLSession sharedSession];
    
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
  
      if(httpResponse.statusCode != 200) {
        [self _sendError];
        return;
      }
      
      NSError *parseError = nil;
      NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
      
      self->_sessionStatus = [[CardKPaymentSessionStatus alloc] init];
      self->_sessionStatus.bindingItems = [responseDictionary objectForKey:@"bindingItems"];
      self->_sessionStatus.bindingEnabled = (BOOL)[responseDictionary[@"bindingEnabled"] boolValue];
      self->_sessionStatus.cvcNotRequired = (BOOL)[responseDictionary[@"cvcNotRequired"] boolValue];
      self-> _sessionStatus.redirect = [responseDictionary objectForKey:@"redirect"];
      
      CardKConfig.shared.bindings = self->_sessionStatus.bindingItems;
      CardKConfig.shared.bindingCVCRequired = !self->_sessionStatus.cvcNotRequired;
      
      if (self->_sessionStatus.redirect != nil) {
        [self _sendRedirectError];
      } else {
        [self _moveChoosePaymentMethodController];
      }
      
      handler(self->_sessionStatus);
    }];
    [dataTask resume];
  }

  - (void) _getProcessBindingFormRequest:(ConfirmChoosedCard *) choosedCard callback: (void (^)(NSDictionary *)) handler {
    NSString *mdOrder = [NSString stringWithFormat:@"%@%@", @"orderId=", CardKConfig.shared.mdOrder];
    NSString *bindingId = [NSString stringWithFormat:@"%@%@", @"bindingId=", choosedCard.cardKBinding.bindingId];
    NSString *cvc = [NSString stringWithFormat:@"%@%@", @"cvc=", choosedCard.cardKBinding.secureCode];
    NSString *language = [NSString stringWithFormat:@"%@%@", @"language=", CardKConfig.shared.language];
    NSString *parameters = [self _urlParameters:@[mdOrder, bindingId, cvc, language]];
    
    NSString *URL = [NSString stringWithFormat:@"%@%@?%@", _url, @"/rest/processBindingForm.do", parameters];
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:URL]];

    request.HTTPMethod = @"POST";

    NSURLSession *session = [NSURLSession sharedSession];

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

        if(httpResponse.statusCode == 200) {
        }
    }];
    [dataTask resume];
  }

- (void) _processFormRequest:(CardKCardView *) cardView cardOwner:(NSString *) cardOwner seToken:(NSString *) seToken callback: (void (^)(NSDictionary *)) handler {
    NSString *mdOrder = [NSString stringWithFormat:@"%@%@", @"MDORDER=", CardKConfig.shared.mdOrder];
    NSString *language = [NSString stringWithFormat:@"%@%@", @"language=", CardKConfig.shared.language];
    NSString *owner = [NSString stringWithFormat:@"%@%@", @"TEXT=", cardOwner];
    NSString *threeDSSDK = [NSString stringWithFormat:@"%@%@", @"threeDSSDK=", @"true"];

    NSString *seTokenParam = [NSString stringWithFormat:@"%@%@", @"seToken=", [seToken stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"]];
    NSString *parameters = [self _urlParameters:@[mdOrder, seTokenParam, language, owner, @"bindingNotNeeded=false", threeDSSDK]];
    NSString *URL = [NSString stringWithFormat:@"%@%@", _url, @"/rest/processform.do"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:URL]];
    request.HTTPMethod = @"POST";
  
    NSData *postData = [parameters dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    [request setHTTPBody:postData];
  
    NSURLSession *session = [NSURLSession sharedSession];

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

      if(httpResponse.statusCode != 200) {
        self->_cardKPaymentError.massage = @"Ошибка запроса данных формы";
        [self->_cardKPaymentFlowDelegate didErrorPaymentFlow:self->_cardKPaymentError];

        return;
      }
      
      NSError *parseError = nil;
      NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];

      
      NSString *redirect = [responseDictionary objectForKey:@"redirect"];
      BOOL is3DSVer2 = (BOOL)[responseDictionary[@"is3DSVer2"] boolValue];
      NSString *errorMessage = [responseDictionary objectForKey:@"error"];
      NSInteger errorCode = [responseDictionary[@"errorCode"] integerValue];
      
      if (errorCode != 0) {
        self->_cardKPaymentError.massage = errorMessage;
        [self->_cardKPaymentFlowDelegate didErrorPaymentFlow: self->_cardKPaymentError];
      } else if (redirect != nil) {
        self->_cardKPaymentError.massage = redirect;
        [self->_cardKPaymentFlowDelegate didErrorPaymentFlow: self->_cardKPaymentError];
      } else if (is3DSVer2){
        RequestParams.shared.threeDSServerTransId = [responseDictionary objectForKey:@"threeDSServerTransId"];
        RequestParams.shared.threeDSSDKKey = [responseDictionary objectForKey:@"threeDSSDKKey"];

        self->_transactionManager.pubKey = RequestParams.shared.threeDSSDKKey;
        dispatch_async(dispatch_get_main_queue(), ^{
          [self->_transactionManager setUpUICustomizationWithIsDarkMode:NO error:nil];
          [self->_transactionManager initializeSdk];
          [self->_transactionManager showProgressDialog];
          NSDictionary *reqParams = [self->_transactionManager getAuthRequestParameters];
          
          RequestParams.shared.threeDSSDKEncData = reqParams[@"threeDSSDKEncData"];
          RequestParams.shared.threeDSSDKEphemPubKey = reqParams[@"threeDSSDKEphemPubKey"];
          RequestParams.shared.threeDSSDKAppId = reqParams[@"threeDSSDKAppId"];
          RequestParams.shared.threeDSSDKTransId = reqParams[@"threeDSSDKTransId"];

          [self _processFormRequestStep2:(CardKCardView *) cardView cardOwner:(NSString *) cardOwner seToken:(NSString *) seToken callback: (void (^)(NSDictionary *)) handler];
        });
      }
    }];
    [dataTask resume];
  }

- (void) _processFormRequestStep2:(CardKCardView *) cardView cardOwner:(NSString *) cardOwner seToken:(NSString *) seToken callback: (void (^)(NSDictionary *)) handler {
    NSString *mdOrder = [NSString stringWithFormat:@"%@%@", @"MDORDER=", CardKConfig.shared.mdOrder];
    NSString *threeDSSDK = [NSString stringWithFormat:@"%@%@", @"threeDSSDK=", @"true"];
    NSString *language = [NSString stringWithFormat:@"%@%@", @"language=", CardKConfig.shared.language];
    NSString *owner = [NSString stringWithFormat:@"%@%@", @"TEXT=", cardOwner];
  
    NSString *seTokenParam = [NSString stringWithFormat:@"%@%@", @"seToken=", [seToken stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"]];
  
    NSString *threeDSSDKEncData = [NSString stringWithFormat:@"%@%@", @"threeDSSDKEncData=", RequestParams.shared.threeDSSDKEncData];
    NSString *threeDSSDKEphemPubKey = [NSString stringWithFormat:@"%@%@", @"threeDSSDKEphemPubKey=", RequestParams.shared.threeDSSDKEphemPubKey];
    NSString *threeDSSDKAppId = [NSString stringWithFormat:@"%@%@", @"threeDSSDKAppId=", RequestParams.shared.threeDSSDKAppId];
    NSString *threeDSSDKTransId = [NSString stringWithFormat:@"%@%@", @"threeDSSDKTransId=", RequestParams.shared.threeDSSDKTransId];
    NSString *threeDSServerTransId = [NSString stringWithFormat:@"%@%@", @"threeDSServerTransId=", RequestParams.shared.threeDSServerTransId];
  
    NSString *parameters = [self _urlParameters:@[mdOrder, threeDSSDK, language, owner, @"bindingNotNeeded=false", threeDSSDKEncData, threeDSSDKEphemPubKey, threeDSSDKAppId, threeDSSDKTransId, threeDSServerTransId, seTokenParam]];

    NSData *postData = [parameters dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    NSString *URL = [NSString stringWithFormat:@"%@%@", _url, @"/rest/processform.do"];
  
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:URL]];

    request.HTTPMethod = @"POST";
    [request setHTTPBody:postData];
  
    NSURLSession *session = [NSURLSession sharedSession];

    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

      if (httpResponse.statusCode != 200) {
        self->_cardKPaymentError.massage = @"Ошибка запроса данных формы";
        [self->_cardKPaymentFlowDelegate didErrorPaymentFlow:self->_cardKPaymentError];

        return;
      }
      
      NSError *parseError = nil;
      NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];

      NSString *redirect = [responseDictionary objectForKey:@"redirect"];
      BOOL is3DSVer2 = (BOOL)[responseDictionary[@"is3DSVer2"] boolValue];
      NSString *errorMessage = [responseDictionary objectForKey:@"error"];
      NSInteger errorCode = [responseDictionary[@"errorCode"] integerValue];
      
      if (errorCode != 0) {
        self->_cardKPaymentError.massage = errorMessage;
        [self->_cardKPaymentFlowDelegate didErrorPaymentFlow: self->_cardKPaymentError];
        [self->_transactionManager closeProgressDialog];
      } else if (redirect != nil) {
        self->_cardKPaymentError.massage = redirect;
        [self->_cardKPaymentFlowDelegate didErrorPaymentFlow: self->_cardKPaymentError];
        [self->_transactionManager closeProgressDialog];
      } else if (is3DSVer2){
        ARes *aRes = [[ARes alloc] init];
        aRes.acsTransID = [responseDictionary objectForKey:@"threeDSAcsTransactionId"];
        aRes.acsReferenceNumber = [responseDictionary objectForKey:@"threeDSAcsRefNumber"];
        aRes.acsSignedContent = [responseDictionary objectForKey:@"threeDSAcsSignedContent"];
        aRes.threeDSServerTransID = RequestParams.shared.threeDSServerTransId;

        [self->_transactionManager handleResponseWithResponseObject:aRes];
      }
    }];
    [dataTask resume];
  }

- (void)_getFinishedPaymentInfo {
  NSString *mdOrder = [NSString stringWithFormat:@"%@%@", @"orderId=", CardKConfig.shared.mdOrder];
  NSString *withCart = [NSString stringWithFormat:@"%@%@", @"withCart=", @"NO"];
  NSString *language = [NSString stringWithFormat:@"%@%@", @"language=", CardKConfig.shared.language];

  NSString *parameters = [self _urlParameters:@[mdOrder, withCart, language]];

  NSString *URL = [NSString stringWithFormat:@"%@%@?%@", _url, @"/rest/getFinishedPaymentInfo.do", parameters];

  NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:URL]];

  request.HTTPMethod = @"GET";

  NSURLSession *session = [NSURLSession sharedSession];

  NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

      if(httpResponse.statusCode == 200) {

      }
  }];
  [dataTask resume];
}

- (void)_unbindСardAnon {
  NSString *mdOrder = [NSString stringWithFormat:@"%@%@", @"orderId=", CardKConfig.shared.mdOrder];
  NSString *bindingId = [NSString stringWithFormat:@"%@%@", @"bindingId=", _cardKBinding.bindingId];
  
  NSString *parameters = [self _urlParameters:@[mdOrder, bindingId]];
  NSString *URL = [NSString stringWithFormat:@"%@%@?%@", _url, @"/binding/unbindcardanon.do", parameters];

  NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:URL]];

  request.HTTPMethod = @"GET";

  NSURLSession *session = [NSURLSession sharedSession];

  NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

      if(httpResponse.statusCode == 200) {

      }
  }];
  [dataTask resume];
}

// CardKDelegate
- (void)cardKPaymentView:(nonnull CardKPaymentView *)paymentView didAuthorizePayment:(nonnull PKPayment *)pKPayment {
  
}

- (void)cardKitViewController:(nonnull UIViewController *)controller didCreateSeToken:(nonnull NSString *)seToken allowSaveBinding:(BOOL)allowSaveBinding isNewCard:(BOOL)isNewCard {
  
  _seToken = seToken;
  if (isNewCard) {
    CardKViewController *cardKViewController = (CardKViewController *) controller;
    [self _processFormRequest: [cardKViewController getCardKView]
                       cardOwner:[cardKViewController getCardOwner]
                        seToken:seToken
                        callback:^(NSDictionary * sessionStatus) {}];
    
  } else {
    ConfirmChoosedCard *confirmChoosedCardController = (ConfirmChoosedCard *) controller;
    _cardKBinding = confirmChoosedCardController.cardKBinding;
    [self _getProcessBindingFormRequest:confirmChoosedCardController
                        callback:^(NSDictionary * sessionStatus) {}];
  }
}

- (void)didLoadController:(nonnull CardKViewController *)controller {
  controller.purchaseButtonTitle = @"Custom purchase button";
  controller.allowSaveBinding = self->_sessionStatus.bindingEnabled;
  controller.isSaveBinding = false;
  controller.displayCardHolderField = true;
}

- (void)didRemoveBindings:(nonnull NSArray<CardKBinding *> *)removedBindings {
  
}

- (void)willShowPaymentView:(nonnull CardKPaymentView *)paymentView {
  NSArray *paymentNetworks = @[PKPaymentNetworkAmex, PKPaymentNetworkDiscover, PKPaymentNetworkMasterCard, PKPaymentNetworkVisa];
 
  PKPaymentSummaryItem *paymentItem = [PKPaymentSummaryItem summaryItemWithLabel:@"Коробка" amount:[[NSDecimalNumber alloc] initWithString:@"0.1"]];
  
  NSString *merchandId = @"merchant.cardkit";
  paymentView.merchantId = merchandId;
  paymentView.paymentRequest.currencyCode = @"RUB";
  paymentView.paymentRequest.countryCode = @"RU";
  paymentView.paymentRequest.merchantIdentifier = merchandId;
  paymentView.paymentRequest.merchantCapabilities = PKMerchantCapability3DS;
  paymentView.paymentRequest.supportedNetworks = paymentNetworks;
  paymentView.paymentRequest.paymentSummaryItems = @[paymentItem];
}

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
  
}
@end
