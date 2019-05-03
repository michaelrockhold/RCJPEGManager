//
//  JPEGManagerException.h
//  JPEGManager
//
//  Created by Michael Rockhold on 7/28/10.
//  Copyright 2010 The Rockhold Company. All rights reserved.
//

#import "RCException.h"

@interface JPEGManagerException : RCException
{
}

// This method takes a nil-terminated list of objects, and returns an autoreleased JPEGManagerException
+(JPEGManagerException*)reason:(NSString*)errorMsgKey, ...;

+(JPEGManagerException*)reason:(NSString*)errorMsgKey args:(NSArray*)args;

-(id)initWithReason:(NSString*)errorMsgKey args:(NSArray*)args;

@end
