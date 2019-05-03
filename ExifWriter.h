//
//  ExifWriter.h
//  JPEGManager
//
//  Created by Michael Rockhold on 7/27/10.
//  Copyright 2010 The Rockhold Company. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "jhead.h"

@interface ExifWriter : NSObject
{
	BOOL _bigendian;
	NSMutableData* _data;
}

@property (nonatomic, readonly) BOOL bigendian;

-(id)initWithBigEndianness:(BOOL)bigEndianness;

-(void)put16u:(uint16_t)putValue;

-(void)put32u:(uint32_t)putValue;

-(void)putURational:(const URational)putValue;

-(void)putSRational:(const SRational)putValue;

-(void)putCoordinateTriple:(const CoordinateTriple)putValue;

-(NSData*)serialize;

-(size_t)declareDirectory:(size_t)entriesCount;
-(size_t)declareDirectoryAt:(size_t)entriesOffset entryNumber:(NSUInteger)entryNumber tag:(int)tag entriesCount:(size_t)entriesCount;

-(void)putOffsetEntryAt:(size_t)entriesOffset entryNumber:(NSUInteger)entryNumber tag:(int)tag;

-(void)putEntryAt:(size_t)entriesOffset entryNumber:(NSUInteger)entryNumber tag:(int)tag fmt:(int)fmt count:(size_t)count data:(uint32_t)data;

-(void)putChar:(uint8_t)c at:(size_t)entriesOffset entryNumber:(NSUInteger)entryNumber tag:(int)tag;

-(void)putString:(NSString*)string at:(size_t)entriesOffset entryNumber:(NSUInteger)entryNumber tag:(int)tag;

-(void)putCoordinateTriple:(const CoordinateTriple)ct at:(size_t)entriesOffset entryNumber:(NSUInteger)entryNumber tag:(int)tag;

-(void)putURational:(const URational)ur at:(size_t)entriesOffset entryNumber:(NSUInteger)entryNumber tag:(int)tag;

-(void)putSRational:(const SRational)sr at:(size_t)entriesOffset entryNumber:(NSUInteger)entryNumber tag:(int)tag;

@end
