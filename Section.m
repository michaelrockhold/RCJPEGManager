//
//  Section.m
//  JPEGManager
//
//  Created by Michael Rockhold on 7/27/10.
//  Copyright 2010 The Rockhold Company. All rights reserved.
//

#import "Section.h"

@implementation Section
@synthesize sectionType = _sectionType, data = _data;

-(id)initWithType:(JPEGMarker_t)SectionType data:(NSData *)data
{
	if ( self = [super init] )
	{
		_sectionType = SectionType;
		_data = [data retain];
	}
	return self;
}

-(void)dealloc
{
	[_data release];
	[super dealloc];
}

-(id)initWithType:(JPEGMarker_t)SectionType bytes:(uint8_t *)bytes length:(size_t)length
{
	return [self initWithType:SectionType data:[NSData dataWithBytesNoCopy:bytes length:length freeWhenDone:NO]];
}

@end