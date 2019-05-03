//
//  ExifReader.m
//  JPEGManager
//
//  Created by Michael Rockhold on 7/27/10.
//  Copyright 2010 The Rockhold Company. All rights reserved.
//

#import "ExifReader.h"
#import "JPEGManager.h"
#import "TagTable.h"
#import "JPEGManagerException.h"
#import "jhead.h"

UIImageOrientation s_exifToUIImageOrientation[] = {
	UIImageOrientationUp,			// exifOrientation_unknown,
	UIImageOrientationUp,			// exifOrientation_top_left,
	UIImageOrientationUpMirrored,	// exifOrientation_top_right,
	UIImageOrientationDown,			// exifOrientation_bottom_right,
	UIImageOrientationDownMirrored,	// exifOrientation_bottom_left,
	UIImageOrientationRightMirrored,// exifOrientation_left_top,
	UIImageOrientationLeft,			// exifOrientation_right_top,
	UIImageOrientationLeftMirrored,	// exifOrientation_right_bottom,
	UIImageOrientationRight			// exifOrientation_left_bottom	
};
const static size_t s_UIImageOrientationCount = sizeof(s_exifToUIImageOrientation) / sizeof(UIImageOrientation);

static UIImageOrientation exifOrientationToUIImageOrientation(ExifOrientation exifOrientation)
{
	unsigned i = (unsigned)exifOrientation;
	return ( i >= s_UIImageOrientationCount )
	? UIImageOrientationUp
	: s_exifToUIImageOrientation[i];	
}


const int BytesPerFormat[] = {0,1,1,2,4,8,1,1,2,4,8,4,8};

@interface ExifReader (PrivateMakerNote)

-(void)ProcessCanonMakerNoteDir:(unsigned char *)DirStart;
-(void)ShowMakerNoteGeneric:(unsigned char *)ValuePtr byteCount:(int)ByteCount;

@end

CLLocationCoordinate2D
MakeLocationCoordinate2D(CoordinateTriple ctLat, BOOL north, CoordinateTriple ctLong, BOOL east)
{
	CLLocationCoordinate2D coord;
	coord.latitude = coordinateTripleToLocationDegrees(ctLat) * (north ? 1 : -1);
	coord.longitude = coordinateTripleToLocationDegrees(ctLong) * (east ? 1 : -1);
	
	return coord;
}

@implementation ExifReader

-(id)initWithJPEGMgr:(JPEGManager*)jpegMgr bytes:(uint8_t*)bytes length:(size_t)length
{
	if ( self = [super init] )
	{
		_jpegMgr = [jpegMgr retain];
		_bytes = bytes;
		_length = length;		
		
	    _jpegMgr.focalplaneXRes = 0;
		_jpegMgr.focalplaneUnits = 0;
		_jpegMgr.exifImageWidth = 0;
		
		NSLog(@"Exif header: section %lx, %d bytes long", _bytes, _length);
		
			// Check the EXIF header component
		static unsigned char ExifHeader[] = "Exif\0\0";
		if ( memcmp(_bytes+2, ExifHeader,6) )
		{
			[[JPEGManagerException reason:@"Invalid EXIF header", nil] raise];
			goto bad;
		}
		
		if (memcmp(_bytes+8,"II",2) == 0)
		{
			NSLog(@"Exif section in little-endian order");
			_bigEndian = NO;
		}
		else if (memcmp(_bytes+8,"MM",2) == 0)
		{
			NSLog(@"Exif section in big-endian order");
			_bigEndian = YES;
		}
		else
		{
			[[JPEGManagerException reason:@"Invalid EXIF alignment marker", nil] raise];
			goto bad;
		}
		
			// Check the next value for correctness.
		if ( [self get16u:_bytes+10] != 0x2A )
		{
			[[JPEGManagerException reason:@"Invalid EXIF header", nil] raise];
			goto bad;
		}
		
		_offsetBase = _bytes + 8;
		_exifLength = _length - 8;
		goto ok;
	bad:
		
		[self dealloc];
		return nil;
		
	ok:
		;
	}
	return self;
}

-(void)dealloc
{
	[_jpegMgr release];
	[super dealloc];
}

-(uint16_t)get16u:(uint8_t*)bytes { return get16u(bytes, _bigEndian); }

-(int32_t)get32s:(uint8_t*)bytes { return get32s(bytes, _bigEndian); }

-(uint32_t)get32u:(uint8_t*)bytes { return get32u(bytes, _bigEndian); }

-(URational)getURational:(uint8_t*)bytes { return getURational(bytes, _bigEndian); }

-(SRational)getSRational:(uint8_t*)bytes { return getSRational(bytes, _bigEndian); }

-(CoordinateTriple)getCoordinateTriple:(uint8_t*)bytes { return getCoordinateTriple(bytes, _bigEndian); }


	//--------------------------------------------------------------------------
	// Process GPS info directory
	//--------------------------------------------------------------------------
-(void)ProcessGpsInfo:(uint8_t*)DirStart byteCount:(size_t)ByteCount
{
    int NumDirEntries = [self get16u:DirStart];
	
	NSLog(@"(dir has %d entries)", NumDirEntries);
	
    _jpegMgr.gpsInfoPresent = TRUE;
	
	NSInteger aboveSealevel = 1;
	BOOL north = YES;
	BOOL east = YES;
	URational urAlt = { 0, 1 };
	CoordinateTriple ctLat;
	CoordinateTriple ctLong;
	
    for (int de=0; de<NumDirEntries; de++)
	{
        unsigned char * DirEntry = dir_entry_address(DirStart, de);
		
        if (DirEntry+12 > _offsetBase + _exifLength)
		{
			[[JPEGManagerException reason:@"Illegally sized EXIF subdirectory (%@ entries)", [NSNumber numberWithUnsignedInt:NumDirEntries], nil] raise];
            return;
        }
		
        JPEGMarker_t Tag = [self get16u:DirEntry];
        JPEGNumberFormat_t Format = [self get16u:DirEntry+2];
        size_t Components = [self get32u:DirEntry+4];
		
        if ((Format-1) >= NUM_FORMATS)
		{
				// (-1) catches illegal zero case as unsigned underflows to positive large.
			[[JPEGManagerException reason:@"Illegal number format %@ for EXIF tag %@", [NSNumber numberWithInt:Format], [NSNumber numberWithInt:Tag], nil] raise];
        }
		
        unsigned char * ValuePtr;
        size_t ByteCount = Components * BytesPerFormat[Format];
		
            // If it's bigger than 4 bytes, the dir entry contains an offset.
            // 4 bytes or less and value is in the dir entry itself
        if (ByteCount > 4)
		{
            unsigned OffsetVal = [self get32u:DirEntry+8];
            if ( OffsetVal+ByteCount > _exifLength )
			{
					// Bogus pointer offset and / or bytecount value
				[[JPEGManagerException reason:@"Illegal value pointer for EXIF tag %@", [NSNumber numberWithUnsignedInt:Tag], nil] raise];
                continue;
            }
            ValuePtr = _offsetBase+OffsetVal;
        }
		else
		{
            ValuePtr = DirEntry+8;
        }
		
        switch(Tag)
		{
            case TAG_GPS_LAT_REF:
                north = 'N' == ValuePtr[0];
                break;
				
            case TAG_GPS_LONG_REF:
                east = 'E' == ValuePtr[0];
                break;
				
            case TAG_GPS_LAT:
                if (Format != FMT_URATIONAL)
				{
					[[JPEGManagerException reason:@"Inappropriate format (%@) for EXIF GPS coordinates!", [NSNumber numberWithInt:Format], nil] raise];
                }
				else
				{
					ctLat = [self getCoordinateTriple:ValuePtr ];
				}
				break;
				
            case TAG_GPS_LONG:
                if (Format != FMT_URATIONAL)
				{
					[[JPEGManagerException reason:@"Inappropriate format (%@) for EXIF GPS coordinates!", [NSNumber numberWithInt:Format], nil] raise];
				}
				else
				{
					ctLong = [self getCoordinateTriple:ValuePtr];
				}
                break;
				
            case TAG_GPS_ALT_REF:
                aboveSealevel = (0 == ValuePtr[0]) ? 1 : -1;
                break;
				
            case TAG_GPS_ALT:
				urAlt = [self getURational:ValuePtr];
                break;
        }		
    }
	
	_jpegMgr.coordinate = MakeLocationCoordinate2D(ctLat, north, ctLong, east);
	_jpegMgr.altitude = urAlt.numerator / urAlt.denominator * aboveSealevel;
	
}

-(BOOL)read 
{	
    size_t FirstOffset = [self get32u:_bytes+12];
    if ( FirstOffset < 8 || FirstOffset > _length-16 )
	{
		[[JPEGManagerException reason:@"Invalid offset (%@) for EXIF IFD value", [NSNumber numberWithInt:FirstOffset], nil] raise];
		return NO;
	}
	
	if ( FirstOffset > 8 )
	{
			// Usually set to 8, but other values valid too.
		NSLog(@"Suspicious offset (%@) for first EXIF IFD value", [NSNumber numberWithInt:FirstOffset]);
	}
	
		// First directory starts 16 bytes in.  All offset are relative to 8 bytes in.
	
	return [self readDirectory:_bytes+8+FirstOffset nestingLevel:0];
}

-(BOOL)readDirectory:(uint8_t*)dirStart nestingLevel:(NSUInteger)nestingLevel
{
    unsigned thumbnailOffset = 0;
    unsigned thumbnailSize = 0;
	
	NSLog(@"ExifReader readDirectory (dirStart %08lx, OffsetBase %08lx, ExifLength %ld, NestingLevel %d)", dirStart, _offsetBase, _exifLength, nestingLevel);
	
    if ( nestingLevel > 4 )
	{
		[[JPEGManagerException reason:@"Corrupt EXIF header: Maximum EXIF directory nesting exceeded (%@)", [NSNumber numberWithInt:nestingLevel], nil] raise];
        return NO;
    }
	
    char IndentString[25];
    memset(IndentString, ' ', 25);
    IndentString[nestingLevel * 4] = '\0';
	
    size_t NumDirEntries = [self get16u:dirStart];
	
	uint8_t* DirEnd = dir_entry_address(dirStart, NumDirEntries);
	if (DirEnd+4 > (_offsetBase+_exifLength))
	{
		if (DirEnd+2 == _offsetBase+_exifLength || DirEnd == _offsetBase+_exifLength)
		{
				// Version 1.3 of jhead would truncate a bit too much.
				// This also caught later on as well.
		}
		else
		{
			[[JPEGManagerException reason:@"Illegally sized EXIF subdirectory (%@ entries)", [NSNumber numberWithUnsignedLong:NumDirEntries], nil] raise];
			return NO;
		}
	}
	
	NSLog(@"Map: %05d-%05d: Directory\n",(int)(dirStart-_offsetBase), (int)(DirEnd+4-_offsetBase));
	
	NSLog(@"(dir has %d entries)\n",NumDirEntries);
	
    for (int de=0; de<NumDirEntries; de++)
	{
        unsigned char * DirEntry = dir_entry_address(dirStart, de);
		
        JPEGMarker_t Tag = (JPEGMarker_t)[self get16u:DirEntry];
        JPEGNumberFormat_t Format = (JPEGNumberFormat_t)[self get16u:DirEntry+2];
        size_t Components = [self get32u:DirEntry+4];
		
        if ((Format-1) >= NUM_FORMATS)
		{
				// (-1) catches illegal zero case as unsigned underflows to positive large.
			[[JPEGManagerException reason:@"Illegal number format %@ for tag %@ in EXIF", [NSNumber numberWithUnsignedInt:Format], [NSNumber numberWithUnsignedInt:Tag], nil] raise];
            continue;
        }
		
        if ( Components > 0x10000 )
		{
			[[JPEGManagerException reason:@"Too many components %@ for tag %@ in EXIF", [NSNumber numberWithUnsignedLong:Components], [NSNumber numberWithUnsignedInt:Tag], nil] raise];
            continue;
        }
		
        unsigned char * ValuePtr;
        size_t ByteCount = Components * BytesPerFormat[Format];
		
        if (ByteCount > 4)
		{
            unsigned OffsetVal = [self get32u:DirEntry+8];
				// If its bigger than 4 bytes, the dir entry contains an offset.
            if (OffsetVal+ByteCount > _exifLength)
			{
					// Bogus pointer offset and / or bytecount value
				[[JPEGManagerException reason:@"Illegal value pointer for EXIF tag %@", [NSNumber numberWithUnsignedInt:Tag], nil] raise];
                continue;
            }
            ValuePtr = _offsetBase+OffsetVal;
			
            if ( YES )
			{
				char* t = TagName(Tag);
				if ( t )
					NSLog(@"Map: %05d-%05d:   Data for tag \'%s\'\n",OffsetVal, OffsetVal+ByteCount, t);
				else 
					NSLog(@"Map: %05d-%05d:   Data for tag %04x\n",OffsetVal, OffsetVal+ByteCount, Tag);
            }
        }
		else
		{
				// 4 bytes or less and value is in the dir entry itself
            ValuePtr = DirEntry+8;
        }
		
        if (Tag == TAG_MAKER_NOTE)
		{
			NSLog(@"%s    Maker note: ",IndentString);
            [self ProcessMakerNote:ValuePtr byteCount:ByteCount];
            continue;
        }
		
        if ( YES )
		{
			NSMutableString* logStr = [NSMutableString stringWithCapacity:32];
			
				// Show tag name			
			char* tagName = TagName(Tag);
			if ( tagName )
			{
				[logStr appendFormat:@"%s%d    %s = ", IndentString, de, tagName];
			}
			else
			{
				[logStr appendFormat:@"%s%d    Unknown Tag %04x Value = ", IndentString, de, Tag];
			}
			
			
				// Show tag value.
            switch(Format)
			{
                case FMT_BYTE:
                    if ( ByteCount>1 )
					{
                        [logStr appendFormat:@"%.*ls\n", ByteCount/2, (wchar_t *)ValuePtr];
                    }
					else
					{
                        [logStr appendString:NumberValue(ValuePtr, Format, ByteCount, _bigEndian)];
                    }
                    break;
					
                case FMT_UNDEFINED:
						// Undefined is typically an ascii string.
                case FMT_STRING:
						// String arrays printed without function call (different from int arrays)
				{
					int NoPrint = 0;
					for (int a=0;a<ByteCount;a++)
					{
						if (ValuePtr[a] >= 32)
						{
							[logStr appendFormat:@"%c", ValuePtr[a]];
							NoPrint = 0;
						}
						else
						{
                                // Avoiding indicating too many unprintable characters of proprietary
                                // bits of binary information this program may not know how to parse.
							if (!NoPrint && a != ByteCount-1)
							{
								[logStr appendString:@"?"];
								NoPrint = 1;
							}
						}
					}
				}
                    break;
					
                default:
						// Handle arrays of numbers later (will there ever be?)
                    [logStr appendString:NumberValue(ValuePtr, Format, ByteCount, _bigEndian)];
            }
			NSLog(@"   readDirectory:offsetBase:exifLength:nestingLevel::%@", logStr);
        }
		
			// Extract useful components of tag
        switch(Tag)
		{
            case TAG_MAKE:
				_jpegMgr.cameraMake = [[[NSString alloc] initWithBytes:(char*)ValuePtr length:ByteCount encoding:NSASCIIStringEncoding] autorelease];
                break;
				
            case TAG_MODEL:
				_jpegMgr.cameraModel = [[[NSString alloc] initWithBytes:(char*)ValuePtr length:ByteCount encoding:NSASCIIStringEncoding] autorelease];
                break;
				
            case TAG_IMAGE_DESCRIPTION:
				_jpegMgr.imageDescription = [[[NSString alloc] initWithBytes:(char*)ValuePtr length:ByteCount encoding:NSASCIIStringEncoding] autorelease];
                break;
				
            case TAG_SOFTWARE:
				_jpegMgr.software = [[[NSString alloc] initWithBytes:(char*)ValuePtr length:ByteCount encoding:NSASCIIStringEncoding] autorelease];
                break;
				
            case TAG_ARTIST:
				_jpegMgr.artist = [[[NSString alloc] initWithBytes:(char*)ValuePtr length:ByteCount encoding:NSASCIIStringEncoding] autorelease];
                break;
				
            case TAG_COPYRIGHT:
				_jpegMgr.copyright = [[[NSString alloc] initWithBytes:(char*)ValuePtr length:ByteCount encoding:NSASCIIStringEncoding] autorelease];
                break;
				
            case TAG_DATETIME_ORIGINAL:
				_jpegMgr.dateTime = [[[NSString alloc] initWithBytes:(char*)ValuePtr length:ByteCount encoding:NSASCIIStringEncoding] autorelease];
					// If we get a DATETIME_ORIGINAL, we use that one.
					// Fallthru...
				
            case TAG_DATETIME_DIGITIZED:
            case TAG_DATETIME:
                if ( _jpegMgr.dateTime )
				{
						// If we don't already have a DATETIME_ORIGINAL, use whatever
						// time fields we may have.
					_jpegMgr.dateTime = [[[NSString alloc] initWithBytes:(char*)ValuePtr length:ByteCount encoding:NSASCIIStringEncoding] autorelease];
                }
				
                if (_jpegMgr.numDateTimeTags >= MAX_DATE_COPIES)
				{
					NSLog(@"Suspiciously large number of data fields (%d) makes the validity of EXIF section seem unlikely", _jpegMgr.numDateTimeTags);
                }
                break;
				
            case TAG_WINXP_COMMENT:
                if ( _jpegMgr.comments ) // We already have a jpeg comment.
				{
						// Skip this one.
                    NSLog(@"Windows XP comment and other comment in header");
                }
				else if ( ByteCount > 1 )
				{
					_jpegMgr.comments = [[[NSString alloc] initWithBytes:(char*)ValuePtr length:ByteCount encoding:NSASCIIStringEncoding] autorelease];
                }
                break;
				
            case TAG_USERCOMMENT:
			{
				int a = 0;
                if (MAX_COMMENT_SIZE) // We already have a jpeg comment, (probably windows comment), skip this one.
				{
                    NSLog(@"Multiple comments in exif header");
                    break;
                }
				
					// Copy the comment
                if (memcmp(ValuePtr, "ASCII",5) == 0)
				{
                    for (a=5;a<10;a++)
					{
                        int c;
                        c = (ValuePtr)[a];
                        if (c != '\0' && c != ' ')
						{
							_jpegMgr.comments = [[[NSString alloc] initWithBytes:(char*)ValuePtr+a length:ByteCount-a encoding:NSASCIIStringEncoding] autorelease];
                            break;
                        }
                    }
                }
				else
				{
					_jpegMgr.comments = [[[NSString alloc] initWithBytes:(char*)ValuePtr+a length:ByteCount-a encoding:NSASCIIStringEncoding] autorelease];
                }
			}
                break;
				
            case TAG_FNUMBER:
					// Simplest way of expressing aperture, so I trust it the most.
					// (overwrite previously computd value if there is one)
                _jpegMgr.apertureFNumber = (float)ConvertAny(ValuePtr, Format, _bigEndian);
                break;
				
            case TAG_APERTURE:
            case TAG_MAXAPERTURE:
					// More relevant info always comes earlier, so only use this field if we don't 
					// have appropriate aperture information yet.
                if ( _jpegMgr.apertureFNumber == 0 )
				{
                    _jpegMgr.apertureFNumber = (float)exp(ConvertAny(ValuePtr, Format, _bigEndian)*log(2)*0.5);
                }
                break;
				
            case TAG_FOCALLENGTH:
					// Nice digital cameras actually save the focal length as a function
					// of how farthey are zoomed in.
                _jpegMgr.focalLength = (float)ConvertAny(ValuePtr, Format, _bigEndian);
                break;
				
            case TAG_SUBJECT_DISTANCE:
					// Inidcates the distacne the autofocus camera is focused to.
					// Tends to be less accurate as distance increases.
                _jpegMgr.distance = (float)ConvertAny(ValuePtr, Format, _bigEndian);
                break;
				
            case TAG_EXPOSURETIME:
					// Simplest way of expressing exposure time, so I trust it most.
					// (overwrite previously computed value if there is one)
                _jpegMgr.exposureTime = (float)ConvertAny(ValuePtr, Format, _bigEndian);
                break;
				
            case TAG_SHUTTERSPEED:
					// More complicated way of expressing exposure time, so only use
					// this value if we don't already have it from somewhere else.
                if ( _jpegMgr.exposureTime == 0 )
				{
                    _jpegMgr.exposureTime = (float)(1/exp(ConvertAny(ValuePtr, Format, _bigEndian)*log(2)));
                }
                break;
				
            case TAG_FLASH:
                _jpegMgr.flashUsed = (int)ConvertAny(ValuePtr, Format, _bigEndian);
                break;
				
            case TAG_ORIENTATION:
				_jpegMgr.orientation = exifOrientationToUIImageOrientation(ConvertAny(ValuePtr, Format, _bigEndian));
                break;
				
            case TAG_PIXEL_Y_DIMENSION:
                _jpegMgr.exifImageLength = (int)ConvertAny(ValuePtr, Format, _bigEndian);
                break;
				
            case TAG_PIXEL_X_DIMENSION:
                _jpegMgr.exifImageWidth = (int)ConvertAny(ValuePtr, Format, _bigEndian);
                break;
				
            case TAG_FOCAL_PLANE_XRES:
                _jpegMgr.focalplaneXRes = ConvertAny(ValuePtr, Format, _bigEndian);
                break;
				
            case TAG_FOCAL_PLANE_UNITS:
                switch((int)ConvertAny(ValuePtr, Format, _bigEndian))
			{
				case 1: _jpegMgr.focalplaneUnits = 25.4; break; // inch
				case 2: 
						// According to the information I was using, 2 means meters.
						// But looking at the Cannon powershot's files, inches is the only
						// sensible value.
					_jpegMgr.focalplaneUnits = 25.4;
					break;
					
				case 3: _jpegMgr.focalplaneUnits = 10;   break;  // centimeter
				case 4: _jpegMgr.focalplaneUnits = 1;    break;  // millimeter
				case 5: _jpegMgr.focalplaneUnits = .001; break;  // micrometer
			}
                break;
				
            case TAG_EXPOSURE_BIAS:
                _jpegMgr.exposureBias = (float)ConvertAny(ValuePtr, Format, _bigEndian);
                break;
				
            case TAG_WHITEBALANCE:
                _jpegMgr.whitebalance = (WhiteBalance_t)ConvertAny(ValuePtr, Format, _bigEndian);
                break;
				
            case TAG_LIGHT_SOURCE:
                _jpegMgr.lightSource = (Lightsource_t)ConvertAny(ValuePtr, Format, _bigEndian);
                break;
				
            case TAG_METERING_MODE:
                _jpegMgr.meteringMode = (MeteringMode_t)ConvertAny(ValuePtr, Format, _bigEndian);
                break;
				
            case TAG_EXPOSURE_PROGRAM:
                _jpegMgr.exposureProgram = (ExposureProgram_t)ConvertAny(ValuePtr, Format, _bigEndian);
                break;
				
            case TAG_EXPOSURE_INDEX:
                if (_jpegMgr.ISOequivalent == 0)
				{
						// Exposure index and ISO equivalent are often used interchangeably,
						// so we will do the same in jhead.
						// http://photography.about.com/library/glossary/bldef_ei.htm
                    _jpegMgr.ISOequivalent = (int)ConvertAny(ValuePtr, Format, _bigEndian);
                }
                break;
				
            case TAG_EXPOSURE_MODE:
                _jpegMgr.exposureMode = (ExposureMode_t)ConvertAny(ValuePtr, Format, _bigEndian);
                break;
				
            case TAG_ISO_EQUIVALENT:
                _jpegMgr.ISOequivalent = (int)ConvertAny(ValuePtr, Format, _bigEndian);
                if ( _jpegMgr.ISOequivalent < 50 )
				{
						// Fixes strange encoding on some older digicams.
                    _jpegMgr.ISOequivalent *= 200;
                }
                break;
				
            case TAG_DIGITALZOOMRATIO:
                _jpegMgr.digitalZoomRatio = (float)ConvertAny(ValuePtr, Format, _bigEndian);
                break;
				
            case TAG_THUMBNAIL_OFFSET:
                thumbnailOffset = (int)ConvertAny(ValuePtr, Format, _bigEndian);
                break;
				
            case TAG_THUMBNAIL_LENGTH:
                thumbnailSize = (int)ConvertAny(ValuePtr, Format, _bigEndian);
                break;
				
            case TAG_EXIF_OFFSET:
            case TAG_INTEROP_OFFSET:
			{
				NSLog(@"%s%s Dir:", IndentString, Tag == TAG_INTEROP_OFFSET ? "Interop" : "Exif");
				
				unsigned char * SubdirStart = _offsetBase + [self get32u:ValuePtr];
				if (SubdirStart < _offsetBase || SubdirStart > _offsetBase+_exifLength)
				{
					[[JPEGManagerException reason:@"Illegal sub-directory link for EXIF offset, interop ofset, or GPS info", nil] raise];
				}
				else
				{
					[self readDirectory:SubdirStart nestingLevel:nestingLevel+1];
				}
				continue;
			}
                break;
				
            case TAG_GPSINFO:
			{
				NSLog(@"%s    GPS info dir:",IndentString);
				
				uint8_t* SubdirStart = _offsetBase + [self get32u:ValuePtr];
				if (SubdirStart < _offsetBase || SubdirStart > _offsetBase+_exifLength)
				{
					[[JPEGManagerException reason:@"Illegal sub-directory link for EXIF offset, interop ofset, or GPS info", nil] raise];
				}
				else
				{
					[self ProcessGpsInfo:SubdirStart byteCount:ByteCount];
				}
				continue;
			}
                break;
				
            case TAG_FOCALLENGTH_35MM:
					// The focal length equivalent 35 mm is a 2.2 tag (defined as of April 2002)
					// if its present, use it to compute equivalent focal length instead of 
					// computing it from sensor geometry and actual focal length.
                _jpegMgr.focalLength35mmEquiv = (unsigned)ConvertAny(ValuePtr, Format, _bigEndian);
                break;
				
            case TAG_DISTANCE_RANGE:
					// Three possible standard values:
					//   1 = macro, 2 = close, 3 = distant
                _jpegMgr.distanceRange = (int)ConvertAny(ValuePtr, Format, _bigEndian);
                break;
								
            case TAG_X_RESOLUTION:
                if ( nestingLevel == 0 ) // Only use the values from the top level directory
				{
                    _jpegMgr.xResolution = (float)ConvertAny(ValuePtr, Format, _bigEndian);
						// if yResolution has not been set, use the value of xResolution
                    if ( _jpegMgr.yResolution == 0.0 ) _jpegMgr.yResolution = _jpegMgr.xResolution;
                }
                break;
				
            case TAG_Y_RESOLUTION:
                if ( nestingLevel == 0 ) // Only use the values from the top level directory
				{
                    _jpegMgr.yResolution = (float)ConvertAny(ValuePtr, Format, _bigEndian);
						// if xResolution has not been set, use the value of yResolution
                    if (_jpegMgr.xResolution == 0.0) _jpegMgr.xResolution = _jpegMgr.yResolution;
                }
                break;
				
            case TAG_RESOLUTION_UNIT:
                if ( nestingLevel == 0 ) // Only use the values from the top level directory
				{
                    _jpegMgr.resolutionUnit = (int)ConvertAny(ValuePtr, Format, _bigEndian);
                }
                break;
				
        }
    }
	
	
		// In addition to linking to subdirectories via exif tags, 
		// there's also a potential link to another directory at the end of each
		// directory.  this has got to be the result of a committee!
	
	if ( dir_entry_address(dirStart, NumDirEntries) + 4 <= _offsetBase + _exifLength )
	{
		unsigned Offset = [self get32u:dirStart+2+12*NumDirEntries];
		if ( Offset )
		{
			unsigned char * SubdirStart = _offsetBase + Offset;
			if (SubdirStart > _offsetBase+_exifLength || SubdirStart < _offsetBase)
			{
				if (SubdirStart > _offsetBase && SubdirStart < _offsetBase+_exifLength+20)
				{
						// Jhead 1.3 or earlier would crop the whole directory!
						// As Jhead produces this form of format incorrectness, 
						// I'll just let it pass silently
					NSLog(@"Thumbnail removed with Jhead 1.3 or earlier\n");
				}
				else
				{
					[[JPEGManagerException reason:@"Illegally sized EXIF subdirectory (%@ entries)", [NSNumber numberWithUnsignedInt:NumDirEntries], nil] raise];
				}
			}
			else
			{
			 	if (SubdirStart <= _offsetBase+_exifLength)
				{
					NSLog(@"%sNested directory ",IndentString);
					[self readDirectory:SubdirStart nestingLevel:nestingLevel+1];
				}
			}
		}
	}
	else
	{
			// The exif header ends before the last next directory pointer.
	}
	
    if ( thumbnailOffset && thumbnailSize )
	{
		_jpegMgr.thumbnail = [NSData dataWithBytesNoCopy:_offsetBase+thumbnailOffset length:thumbnailSize freeWhenDone:NO];
    }
	return YES;
}

	//--------------------------------------------------------------------------
	// Process maker note - to the limited extent that its supported.
	//--------------------------------------------------------------------------
-(void)ProcessMakerNote:(unsigned char *)DirStart byteCount:(int)ByteCount
{
    if ( [_jpegMgr.cameraMake rangeOfString:@"Canon"].location != NSNotFound )
	{
        [self ProcessCanonMakerNoteDir:DirStart];
    }
	else // generic
	{
		[self ShowMakerNoteGeneric:DirStart byteCount:ByteCount];
    }
}

	//--------------------------------------------------------------------------
	// Process exif format directory, as used by Canon maker note
	//--------------------------------------------------------------------------
-(void)ProcessCanonMakerNoteDir:(unsigned char *)DirStart
{
    size_t NumDirEntries = [self get16u:DirStart];
	NSLog(@"(dir has %d entries)\n", NumDirEntries);
	
	uint8_t* DirEnd = dir_entry_address(DirStart, NumDirEntries);
	if ( DirEnd > (_offsetBase+_exifLength))
	{
		[[JPEGManagerException reason:@"Illegally sized EXIF subdirectory (%@ entries)", [NSNumber numberWithUnsignedLong:NumDirEntries], nil] raise];
		return;
	}
	
	NSLog(@"Map: %05d-%05d: Directory (makernote)\n",(int)(DirStart-_offsetBase), (int)(DirEnd-_offsetBase));
	
    for (int de=0; de<NumDirEntries; de++)
	{
        uint8_t* DirEntry = dir_entry_address(DirStart, de);
		
		JPEGMarker_t Tag = (JPEGMarker_t)[self get16u:DirEntry];
        JPEGNumberFormat_t format = (JPEGNumberFormat_t)[self get16u:DirEntry+2];
        size_t Components = [self get32u:DirEntry+4];
		
        if ( (format-1) >= NUM_FORMATS )
		{
				// (-1) catches illegal zero case as unsigned underflows to positive large.
			[[JPEGManagerException reason:@"Illegal number format %@ for EXIF tag %@", [NSNumber numberWithUnsignedInt:format], [NSNumber numberWithUnsignedInt:Tag], nil] raise];
            continue;
        }
		
        if ( Components > 0x10000)
		{
			[[JPEGManagerException reason:@"Too many components %@ for tag %@ in EXIF", [NSNumber numberWithUnsignedLong:Components], [NSNumber numberWithUnsignedInt:Tag], nil] raise];
            continue;
        }
		
        uint8_t* ValuePtr;
        size_t ByteCount = Components * BytesPerFormat[format];
		
        if (ByteCount > 4)
		{
            unsigned OffsetVal = [self get32u:DirEntry+8];
				// If its bigger than 4 bytes, the dir entry contains an offset.
            if ( OffsetVal+ByteCount > _exifLength )
			{
					// Bogus pointer offset and / or bytecount value
				[[JPEGManagerException reason:@"Illegal value pointer for EXIF tag %@", [NSNumber numberWithUnsignedInt:Tag], nil] raise];
                continue;
            }
            ValuePtr = _offsetBase+OffsetVal;
			
			NSLog(@"Map: %05d-%05d:   Data for makernote tag %04x\n", OffsetVal, OffsetVal+ByteCount, Tag);
        }
		else
		{
				// 4 bytes or less and value is in the dir entry itself
            ValuePtr = DirEntry+8;
        }
		
			// Show tag name
		NSLog(@"            Canon maker tag %04x Value = ", Tag);
		
			// Show tag value.
        switch(format)
		{
            case FMT_UNDEFINED:
					// Undefined is typically an ascii string.
            case FMT_STRING:
					// String arrays printed without function call (different from int arrays)
                if ( YES )
				{
					NSMutableString* logStr = [NSMutableString stringWithCapacity:32];
					int ZeroSkipped = 0;
                    for (int a=0; a<ByteCount; a++)
					{
                        if (ValuePtr[a] >= 32)
						{
                            if (ZeroSkipped)
							{
								[logStr appendString:@"?"];
                                ZeroSkipped = 0;
                            }
							[logStr appendFormat:@"%c",ValuePtr[a]];
                        }
						else
						{
                            if (ValuePtr[a] == 0)
							{
                                ZeroSkipped = 1;
                            }
                        }
                    }
					NSLog(@"\"%@\"\n", logStr);
                }
                break;
				
            default:
				NSLog(@"ProcessCanonMakerNoteDir:offsetBase:exifLength::%@", NumberValue(ValuePtr, format, ByteCount, _bigEndian));
				break;
        }
        if (Tag == 1 && Components > 16)
		{
            int IsoCode = [self get16u:ValuePtr + 16*sizeof(unsigned short)];
            if (IsoCode >= 16 && IsoCode <= 24)
			{
                _jpegMgr.ISOequivalent = 50 << (IsoCode-16);
            } 
        }
		
        if (Tag == 4 && format == FMT_USHORT)
		{
            if (Components > 7)
			{
				uint16_t canonWhitebalance = (uint16_t)[self get16u:ValuePtr + 7*sizeof(unsigned short)];
                switch(canonWhitebalance)
				{
							// 0=Auto, 6=Custom
                    case 1: _jpegMgr.lightSource = Lightsource_Daylight; break;
                    case 2: _jpegMgr.lightSource = Lightsource_Daylight; break;
                    case 3: _jpegMgr.lightSource = Lightsource_Incandescent; break;
                    case 4: _jpegMgr.lightSource = Lightsource_Fluorescent; break;
                    case 5: _jpegMgr.lightSource = Lightsource_Flash; break;
					default:_jpegMgr.lightSource = Lightsource_Undefined; break;
                }
            }
            if (Components > 19 && _jpegMgr.distance <= 0)
			{
					// Indicates the distance the autofocus camera is focused to.
					// Tends to be less accurate as distance increases.
                int temp_dist = [self get16u:ValuePtr + 19*sizeof(unsigned short)];
				_jpegMgr.distance = (temp_dist == 65535) 
				? -1
				:(float)temp_dist/100;
            }
        }
    }
}

	//--------------------------------------------------------------------------
	// Show generic maker note - just hex bytes.
	//--------------------------------------------------------------------------
-(void)ShowMakerNoteGeneric:(unsigned char *)ValuePtr byteCount:(int)ByteCount
{
	NSMutableString* noteStr = [NSMutableString stringWithCapacity:32];
	
    for (int a=0;a<ByteCount;a++)
	{
        if (a > 10)
		{
			[noteStr appendString:@"..."];
            break;
        }
		[noteStr appendFormat:@" %02x", ValuePtr[a]];
    }
	[noteStr appendFormat:@" (%d bytes)", ByteCount];
	
	NSLog(@"ShowMakerNoteGeneric:byteCount::%@", noteStr);
}

@end

