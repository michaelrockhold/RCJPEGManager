//
//  ExifWriter.m
//  JPEGManager
//
//  Created by Michael Rockhold on 7/27/10.
//  Copyright 2010 The Rockhold Company. All rights reserved.
//

#import "ExifWriter.h"
#import "jhead.h"

#define ENTRYSIZE 12

@implementation ExifWriter
@synthesize bigendian = _bigendian;

-(id)initWithBigEndianness:(BOOL)bigEndianness
{
	if ( self = [super init] )
	{
		_bigendian = bigEndianness;
		
		_data = [[NSMutableData dataWithLength:16] retain];
		
		[_data replaceBytesInRange:NSMakeRange(0, 10) withBytes:(_bigendian ? "\0\0Exif\0\0MM" : "\0\0Exif\0\0II") length:10];
		
		uint8_t* p = [_data mutableBytes];
		p += 10;
		
		p = put16u(p, _bigendian, 0x2a);
		
			// first IFD offset. The value written here is the actual offset of the beginning of the top-level
			// directory from the position of the 8-byte '\0\0Exif\0\0' header, so for instance, a value of 8 
			// would indicate that the first IFD starts immediately afterwards, which we assume.
		put32u(p, _bigendian, 8);
	}
	return self;
}

-(void)dealloc
{
	[_data release];
	[super dealloc];
}

-(NSData*)serialize
{
	size_t totalSize = _data.length;
	
	uint8_t buffer[2];
	buffer[0] = (uint8_t)(totalSize >> 8);
    buffer[1] = (uint8_t)totalSize;
	
		// insert the two-byte size information at the front of the exif data
	[_data replaceBytesInRange:NSMakeRange(0, 2) withBytes:buffer length:2];
	
	return _data;
}

-(size_t)declareDirectory:(size_t)entriesCount
{
	[self put16u:entriesCount];
	size_t d = _data.length;
	uint8_t entriesBuf[ENTRYSIZE] = { 0 };
	for (int i=0; i<entriesCount; i++)
		[_data appendBytes:entriesBuf length:ENTRYSIZE];
	[self put32u:0];
	return d;
}

-(size_t)declareDirectoryAt:(size_t)entriesOffset entryNumber:(NSUInteger)entryNumber tag:(int)tag entriesCount:(size_t)entriesCount
{
	[self putOffsetEntryAt:entriesOffset entryNumber:entryNumber tag:tag];
	return [self declareDirectory:entriesCount];
}

-(void)put16u:(uint16_t)putValue
{
	uint8_t Value[2];
	
	put16u(Value, self.bigendian, putValue);
	
	[_data appendBytes:Value length:2];
}

-(void)put32u:(uint32_t)ui
{
	uint8_t Value[4];
	
	put32u(Value, self.bigendian, ui);
	
	[_data appendBytes:Value length:4];
}

-(void)putURational:(const URational)putValue
{
	[self put32u:putValue.numerator];
	[self put32u:putValue.denominator];
}

-(void)putSRational:(const SRational)putValue
{
	[self put32u:putValue.numerator];
	[self put32u:putValue.denominator];
}

-(void)putCoordinateTriple:(const CoordinateTriple)putValue
{
	[self putURational:putValue.degrees];
	[self putURational:putValue.minutes];
	[self putURational:putValue.seconds];
}

-(void)putOffsetEntryAt:(size_t)entriesOffset entryNumber:(NSUInteger)entryNumber tag:(int)tag
{
	[self putEntryAt:entriesOffset entryNumber:entryNumber tag:tag fmt:FMT_ULONG count:1 data:_data.length-8];
}

-(void)putEntryAt:(size_t)entriesOffset entryNumber:(NSUInteger)entryNumber tag:(int)tag fmt:(int)fmt count:(size_t)count data:(uint32_t)data
{
	uint8_t entryBuffer[ENTRYSIZE] = { 0 };
	
	uint8_t* next = put16u(entryBuffer, self.bigendian, tag);
	next = put16u(next, self.bigendian, fmt);
	next = put32u(next, self.bigendian, count);
	next = put32u(next, self.bigendian, data);
	
	[_data replaceBytesInRange:NSMakeRange(entriesOffset+ENTRYSIZE*entryNumber, ENTRYSIZE) withBytes:entryBuffer length:ENTRYSIZE];
}

-(void)putChar:(uint8_t)c at:(size_t)entriesOffset entryNumber:(NSUInteger)entryNumber tag:(int)tag
{
	uint32_t i = c;
	[self putEntryAt:entriesOffset entryNumber:entryNumber tag:tag fmt:FMT_STRING count:1 data:i << 24];
}

-(void)putString:(NSString*)string at:(size_t)entriesOffset entryNumber:(NSUInteger)entryNumber tag:(int)tag
{
	const char* utf8Str = [string UTF8String];
	size_t stringLen = strlen(utf8Str) + 1;
	
	[self putEntryAt:entriesOffset entryNumber:entryNumber tag:tag fmt:FMT_STRING count:stringLen data:_data.length - 8];
	
	[_data appendBytes:utf8Str length:stringLen];
}

-(void)putCoordinateTriple:(const CoordinateTriple)ct at:(size_t)entriesOffset entryNumber:(NSUInteger)entryNumber tag:(int)tag
{
	[self putEntryAt:entriesOffset entryNumber:entryNumber tag:tag fmt:FMT_URATIONAL count:3 data:_data.length-8];
	[self putCoordinateTriple:ct];
}

-(void)putURational:(const URational)ur at:(size_t)entriesOffset entryNumber:(NSUInteger)entryNumber tag:(int)tag
{
	[self putEntryAt:entriesOffset entryNumber:entryNumber tag:tag fmt:FMT_URATIONAL count:1 data:_data.length-8];
	[self putURational:ur];
}

-(void)putSRational:(const SRational)sr at:(size_t)entriesOffset entryNumber:(NSUInteger)entryNumber tag:(int)tag
{
	[self putEntryAt:entriesOffset entryNumber:entryNumber tag:tag fmt:FMT_SRATIONAL count:1 data:_data.length-8];
	[self putSRational:sr];
}

@end
