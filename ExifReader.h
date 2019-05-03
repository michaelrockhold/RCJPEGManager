//
//  ExifReader.h
//  JPEGManager
//
//  Created by Michael Rockhold on 7/27/10.
//  Copyright 2010 The Rockhold Company. All rights reserved.
//
#import <Foundation/Foundation.h>
#import "jhead.h"

@class JPEGManager;

@interface ExifReader : NSObject
{
	JPEGManager*	_jpegMgr;
	uint8_t*		_bytes;
	size_t			_length;
	
	uint8_t* _offsetBase;
	size_t _exifLength;
	BOOL _bigEndian;	
}

-(id)initWithJPEGMgr:(JPEGManager*)jpegMgr bytes:(uint8_t*)bytes length:(size_t)length;

-(BOOL)read;

-(BOOL)readDirectory:(uint8_t*)dirStart nestingLevel:(NSUInteger)nestingLevel;

-(void)ProcessMakerNote:(unsigned char *)DirStart byteCount:(int)ByteCount;

-(void)ProcessGpsInfo:(uint8_t*)ValuePtr byteCount:(size_t)ByteCount;

-(uint16_t)get16u:(uint8_t*)bytes;

-(int32_t)get32s:(uint8_t*)bytes;

-(uint32_t)get32u:(uint8_t*)bytes;

-(URational)getURational:(uint8_t*)bytes;

-(SRational)getSRational:(uint8_t*)bytes;

-(CoordinateTriple)getCoordinateTriple:(uint8_t*)bytes;

@end
