//
//  Section.h
//  JPEGManager
//
//  Created by Michael Rockhold on 7/27/10.
//  Copyright 2010 The Rockhold Company. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "jhead.h"

	// This structure is used to store jpeg file sections in memory.
@interface Section : NSObject
{
	JPEGMarker_t _sectionType;
	NSData* _data;
}

@property (nonatomic, readonly) JPEGMarker_t sectionType;

@property (nonatomic, retain, readonly) NSData* data;

-(id)initWithType:(JPEGMarker_t)SectionType data:(NSData*)data;

-(id)initWithType:(JPEGMarker_t)SectionType bytes:(uint8_t*)bytes length:(size_t)length;

@end
