//
//  JPEGManagerException.m
//  JPEGManager
//
//  Created by Michael Rockhold on 7/28/10.
//  Copyright 2010 The Rockhold Company. All rights reserved.
//

#import "JPEGManagerException.h"

@implementation JPEGManagerException

// This method takes a nil-terminated list of objects, and returns an autoreleased JPEGManagerException
+(JPEGManagerException*)reason:(NSString*)errorMsgKey, ...
{
	id eachObject;
	va_list argumentList;
	NSMutableArray* args = [NSMutableArray arrayWithCapacity:2];
	
	va_start(argumentList, errorMsgKey);			// Start scanning for arguments after errorMsgKey.
	while (eachObject = va_arg(argumentList, id))	// As many times as we can get an argument of type "id"
		[args addObject: eachObject];               // that isn't nil, add it to self's contents.
	va_end(argumentList);
	
	return [JPEGManagerException reason:errorMsgKey args:args];
}

+(JPEGManagerException*)reason:(NSString*)errorMsgKey args:(NSArray*)args
{
	return [[[JPEGManagerException alloc] initWithReason:errorMsgKey args:args] autorelease];
}

-(id)initWithReason:(NSString*)errorMsgKey args:(NSArray*)args
{
	self = [super initWithSubDomain:@"JPEGManager" erroMsgKey:errorMsgKey args:args];
	return self;
}

@end
