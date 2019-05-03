//
//  JPEGHeader.m
//
//  Created by Michael Rockhold on 1/4/10.
//  Copyright 2010 The Rockhold Company. All rights reserved.
//
//  This code owes a great deal to the jhead tool written and
//  placed into the public domain by Matthias Wandel.

#import "jhead.h"
#import "JPEGManager.h"
#import "ExifReader.h"
#import "ExifWriter.h"
#import "Section.h"
#import "TagTable.h"
#import "JPEGManagerException.h"

	//--------------------------------------------------------------------------
	// Table of Jpeg encoding process names
const TagTable_t ProcessTable[] = {
    { M_SOF0,   "Baseline"},
    { M_SOF1,   "Extended sequential"},
    { M_SOF2,   "Progressive"},
    { M_SOF3,   "Lossless"},
    { M_SOF5,   "Differential sequential"},
    { M_SOF6,   "Differential progressive"},
    { M_SOF7,   "Differential lossless"},
    { M_SOF9,   "Extended sequential, arithmetic coding"},
    { M_SOF10,  "Progressive, arithmetic coding"},
    { M_SOF11,  "Lossless, arithmetic coding"},
    { M_SOF13,  "Differential sequential, arithmetic coding"},
    { M_SOF14,  "Differential progressive, arithmetic coding"},
    { M_SOF15,  "Differential lossless, arithmetic coding"},
};

#define PROCESS_TABLE_SIZE  (sizeof(ProcessTable) / sizeof(TagTable_t))

#define PSEUDO_IMAGE_MARKER 0x123 // Extra value.

	//--------------------------------------------------------------------------
	// Get 16 bits motorola order (always) for jpeg header stuff.
	//--------------------------------------------------------------------------
static int Get16m(const void * Short)
{
    return (((unsigned char *)Short)[0] << 8) | ((unsigned char *)Short)[1];
}

UIImageOrientationDesc s_UIImageToExifOrientation[] = {
	{ @"UIImageOrientationUp",				exifOrientation_top_left },		// UIImageOrientationUp
	{ @"UIImageOrientationDown",			exifOrientation_bottom_right },	// UIImageOrientationDown
	{ @"UIImageOrientationLeft",			exifOrientation_right_top },		// UIImageOrientationLeft
	{ @"UIImageOrientationRight",			exifOrientation_left_bottom },	// UIImageOrientationRight
	{ @"UIImageOrientationUpMirrored",		exifOrientation_top_right },		// UIImageOrientationUpMirrored
	{ @"UIImageOrientationDownMirrored",	exifOrientation_bottom_left },	// UIImageOrientationDownMirrored
	{ @"UIImageOrientationLeftMirrored",	exifOrientation_right_bottom },	// UIImageOrientationLeftMirrored
	{ @"UIImageOrientationRightMirrored",	exifOrientation_left_top }		// UIImageOrientationRightMirrored
};

const static size_t s_exifOrientationCount = sizeof(s_UIImageToExifOrientation) / sizeof(UIImageOrientationDesc);

static ExifOrientation UIImageOrientationToExifOrientation(UIImageOrientation imageOrientation)
{
	unsigned i = (unsigned)imageOrientation;
	return ( i >= s_exifOrientationCount )
	? exifOrientation_unknown
	: s_UIImageToExifOrientation[i].exifOrientation;	
}

#pragma mark -

	// 1 - "The 0th row is at the visual top of the image,    and the 0th column is the visual left-hand side."
	// 2 - "The 0th row is at the visual top of the image,    and the 0th column is the visual right-hand side."
	// 3 - "The 0th row is at the visual bottom of the image, and the 0th column is the visual right-hand side."
	// 4 - "The 0th row is at the visual bottom of the image, and the 0th column is the visual left-hand side."

	// 5 - "The 0th row is the visual left-hand side of of the image,  and the 0th column is the visual top."
	// 6 - "The 0th row is the visual right-hand side of of the image, and the 0th column is the visual top."
	// 7 - "The 0th row is the visual right-hand side of of the image, and the 0th column is the visual bottom."
	// 8 - "The 0th row is the visual left-hand side of of the image,  and the 0th column is the visual bottom."

	// Note: The descriptions here are the same as the name of the command line
	// option to pass to jpegtran to right the image

const char * OrientTab[9] = {
    "Undefined",
    "Normal",           // 1
    "flip horizontal",  // left right reversed mirror
    "rotate 180",       // 3
    "flip vertical",    // upside down mirror
    "transpose",        // Flipped about top-left <--> bottom-right axis.
    "rotate 90",        // rotate 90 cw to right it.
    "transverse",       // flipped about top-right <--> bottom-left axis
    "rotate 270",       // rotate 270 to right it.
};

NSString* OrientationDesc(UIImageOrientation io)
{
	return s_UIImageToExifOrientation[io].name;
}

@interface JPEGManager (PrivateMethods)

-(void)description_IPTC:(NSData*)sectionData into:(NSMutableString*)desc;

@end


@implementation JPEGManager

@synthesize imageData = _imageData, sections = _sections;
@synthesize cameraMake = _cameraMake, cameraModel = _cameraModel, imageDescription = _imageDescription, orientation = _orientation;
@synthesize dateTime = _dateTime, numDateTimeTags = _numDateTimeTags;
@synthesize height = _height, width = _width, isColor = _isColor, process = _process, flashUsed = _flashUsed;
@synthesize software = _software, artist = _artist, copyright = _copyright;
@synthesize coordinate = _coordinate, altitude = _altitude;

@synthesize focalLength = _focalLength, focalLength35mmEquiv = _focalLength35mmEquiv, 
	exposureTime = _exposureTime,
	apertureFNumber = _apertureFNumber,
	distance = _distance,
	CCDWidth = _CCDWidth,
	exposureBias = _exposureBias,
	digitalZoomRatio = _digitalZoomRatio,
	whitebalance = _whitebalance,
	meteringMode = _meteringMode,
	exposureProgram = _exposureProgram, exposureMode = _exposureMode,
	ISOequivalent = _ISOequivalent,
	lightSource = _lightSource,
	distanceRange = _distanceRange;

@synthesize JfifHeaderPresent = _JfifHeaderPresent, JfifHeaderResolutionUnits = _JfifHeaderResolutionUnits, JfifHeaderXDensity = _JfifHeaderXDensity, JfifHeaderYDensity = _JfifHeaderYDensity;

@synthesize	focalplaneXRes = _focalplaneXRes, focalplaneUnits = _focalplaneUnits;
@synthesize exifImageWidth = _exifImageWidth, exifImageLength = _exifImageLength;

@synthesize	xResolution = _xResolution, yResolution = _yResolution, resolutionUnit = _resolutionUnit;

@synthesize gpsInfoPresent = _gpsInfoPresent;

+(NSData*)dataWithImage:(UIImage*)image
			   location:(CLLocation*)location 
				  title:(NSString*)title 
				comment:(NSString*)comment
				 artist:(NSString*)artist
			   software:(NSString*)software
			  copyright:(NSString*)copyright
{
	JPEGManager* mgr = nil;
	NSData* d = nil;
	
	@try
	{
		mgr = [[JPEGManager alloc] init];
		[mgr readJpegSections:UIImageJPEGRepresentation(image, 1.0)];
		mgr.comments = comment;
		mgr.cameraMake = @"Apple";
		mgr.cameraModel = [[UIDevice currentDevice] model];
		mgr.imageDescription = title;
		mgr.artist = NSFullUserName();
		
		mgr.software = @"OpenStreetMap @ http://www.openstreetmap.org";
		mgr.copyright = @"OpenStreetMap data is licensed under the Creative Commons Attribution-Share Alike 2.0 Generic License";
		
		mgr.orientation = UIImageOrientationUp;
		
		mgr.coordinate = location.coordinate;
		mgr.altitude = location.altitude;
		
		d = [mgr createJPEGData];
	}
	@finally
	{
		[mgr release];
	}

	return [d autorelease];
}

-(id)init
{
	if ( self = [super init] )
	{
		_imageData = nil;
		_thumbnail = nil;
		
		_sections = [[NSMutableArray arrayWithCapacity:5] retain];
		
			// Start with an empty image information structure.
		_flashUsed = -1;
		_meteringMode = MeteringMode_None;
		_whitebalance = WhiteBalance_Auto;
		_gpsInfoPresent = NO;
	}
	return self;
}

-(void)dealloc
{
	[_sections release];
	[_imageData release];
	[super dealloc];
}

-(NSString*)comments
{
	Section* commentSection = [self findSection:M_COM];
	if ( nil == commentSection )
		return nil;
	
	uint8_t* commentBytes = (uint8_t*)[commentSection.data bytes];
	
	return [[[NSString alloc] initWithBytes:commentBytes+2 length:commentSection.data.length-2 encoding:NSASCIIStringEncoding] autorelease];
}

-(void)setComments:(NSString*)v
{
	const char* commentCStr = [v UTF8String];

	int size = strlen(commentCStr) + 2;
	if ( size > MAX_COMMENT_SIZE + 2 )
	{
		NSLog(@"WARNING: comment too long; will add truncated version to image file");
		size = MAX_COMMENT_SIZE + 2;
	}

	[self removeSectionType:M_COM];
	
	NSMutableData* commentData = [NSMutableData dataWithLength:size];
	uint8_t temp[2];
	temp[0] = (uint8_t)(size>>8);
	temp[1] = (uint8_t)(size);
	
	[commentData replaceBytesInRange:NSMakeRange(0,2)  withBytes:&temp[0]];
	[commentData replaceBytesInRange:NSMakeRange(2,size-2)  withBytes:commentCStr];
	
	Section* commentSection = [[Section alloc] initWithType:M_COM data:commentData];
	[self addCommentSection:commentSection];
	[commentSection release];
}

	//--------------------------------------------------------------------------
	// Show the collected image info, displaying camera F-stop and shutter speed
	// in a consistent and legible fashion.
	//--------------------------------------------------------------------------
-(NSString*)description
{
	NSMutableString* desc = [NSMutableString stringWithCapacity:64];
	
    if ( self.cameraMake )
	{
		[desc appendFormat:@"Camera make  : %@\nCamera model : %@\n", self.cameraMake, self.cameraModel];
    }
    if ( self.dateTime )
	{
        [desc appendFormat:@"Date/Time    : %@\n", self.dateTime];
    }
    [desc appendFormat:@"Resolution   : %d x %d\n", self.width, self.height];
	
    if ( self.orientation != UIImageOrientationUp )
	{
			// Only print orientation if one was supplied, and if its not 1 (normal orientation)
        [desc appendFormat:@"Orientation  : %@\n", OrientationDesc(self.orientation)];
    }
	
    if ( !self.isColor )
	{
        [desc appendString:@"Color/bw     : Black and white\n"];
    }
	
    if ( self.flashUsed != 0 )
	{
		[desc appendString:@"Flash used   : "];
        if ( self.flashUsed & 1 )
		{    
            [desc appendString:@"Yes"];
            switch ( self.flashUsed )
			{
	            case 0x5: [desc appendString:@" (Strobe light not detected)"]; break;
	            case 0x7: [desc appendString:@" (Strobe light detected) "]; break;
	            case 0x9: [desc appendString:@" (manual)"]; break;
	            case 0xd: [desc appendString:@" (manual, return light not detected)"]; break;
	            case 0xf: [desc appendString:@" (manual, return light  detected)"]; break;
	            case 0x19:[desc appendString:@" (auto)"]; break;
	            case 0x1d:[desc appendString:@" (auto, return light not detected)"]; break;
	            case 0x1f:[desc appendString:@" (auto, return light detected)"]; break;
	            case 0x41:[desc appendString:@" (red eye reduction mode)"]; break;
	            case 0x45:[desc appendString:@" (red eye reduction mode return light not detected)"]; break;
	            case 0x47:[desc appendString:@" (red eye reduction mode return light  detected)"]; break;
	            case 0x49:[desc appendString:@" (manual, red eye reduction mode)"]; break;
	            case 0x4d:[desc appendString:@" (manual, red eye reduction mode, return light not detected)"]; break;
	            case 0x4f:[desc appendString:@" (red eye reduction mode, return light detected)"]; break;
	            case 0x59:[desc appendString:@" (auto, red eye reduction mode)"]; break;
	            case 0x5d:[desc appendString:@" (auto, red eye reduction mode, return light not detected)"]; break;
	            case 0x5f:[desc appendString:@" (auto, red eye reduction mode, return light detected)"]; break;
            }
        }
		else
		{
            [desc appendString:@"No"];
            switch ( self.flashUsed )
			{
	            case 0x18:[desc appendString:@" (auto)"]; break;
            }
        }
		[desc appendString:@"\n"];
    }
	
    if ( self.focalLength )
	{
        [desc appendFormat:@"Focal length : %4.1fmm",(double)self.focalLength];
        if (self.focalLength35mmEquiv)
		{
            [desc appendFormat:@"  (35mm equivalent: %dmm)", self.focalLength35mmEquiv];
        }
		[desc appendString:@"\n"];
    }
	
    if (self.digitalZoomRatio > 1)
	{
			// Digital zoom used.  Shame on you!
        [desc appendFormat:@"Digital Zoom : %1.3fx\n", (double)self.digitalZoomRatio];
    }
	
    if (self.CCDWidth)
	{
        [desc appendFormat:@"CCD width    : %4.2fmm\n",(double)self.CCDWidth];
    }
	
    if (self.exposureTime)
	{
		NSMutableString* fmtStr = [NSMutableString stringWithCapacity:32];
		[fmtStr appendString:(self.exposureTime < 0.010) ? @"Exposure time: %6.4f s " : @"Exposure time: %5.3f s "];
        
        if (self.exposureTime <= 0.5)
		{
			[fmtStr appendString:@" (1/%d)"];
            [desc appendFormat:fmtStr, (double)self.exposureTime, (int)(0.5 + 1/self.exposureTime)];
        }
		else
		{
			[desc appendFormat:fmtStr, (double)self.exposureTime];
		}
		[desc appendString:@"\n"];
    }
	
    if (self.apertureFNumber)
	{
        [desc appendFormat:@"Aperture     : f/%3.1f\n",(double)self.apertureFNumber];
    }
	
    if (self.distance)
	{
        if (self.distance < 0)
		{
            [desc appendString:@"Focus dist.  : Infinite\n"];
        }
		else
		{
            [desc appendFormat:@"Focus dist.  : %4.2fm\n",(double)self.distance];
        }
    }
	
    if (self.ISOequivalent)
	{
        [desc appendFormat:@"ISO equiv.   : %2d\n",(int)self.ISOequivalent];
    }
	
    if (self.exposureBias)
	{
			// If exposure bias was specified, but set to zero, presumably its no bias at all,
			// so only show it if its nonzero.
        [desc appendFormat:@"Exposure bias: %4.2f\n",(double)self.exposureBias];
    }
	
    switch(self.whitebalance)
	{
        case WhiteBalance_Manual:
            [desc appendString:@"Whitebalance : Manual\n"];
            break;
        case WhiteBalance_Auto:
            [desc appendString:@"Whitebalance : Auto\n"];
            break;
		default:
			[desc appendFormat:@"Whitebalance : unknown (%d)\n", (unsigned)self.whitebalance];
			break;
    }
	
		//Quercus: 17-1-2004 Added LightSource, some cams return this, whitebalance or both
	NSString* lsStr = nil;
    switch(self.lightSource) {
        case Lightsource_Daylight:		lsStr = @"Daylight"; break;
        case Lightsource_Fluorescent:	lsStr = @"Fluorescent"; break;
        case Lightsource_Incandescent:	lsStr = @"Incandescent"; break;
        case Lightsource_Flash: lsStr = @"Flash"; break;
        case Lightsource_FineWeather: lsStr = @"Fine weather"; break;
        case Lightsource_Shade: lsStr = @"Shade"; break;
        default: lsStr = [NSString stringWithFormat:@"unknown (%d)", (unsigned)self.lightSource]; break;
    }
	[desc appendFormat:@"Light Source : %@\n", lsStr];
	
    if ( self.meteringMode != MeteringMode_None )
	{
		NSString* mmStr = nil;
        switch( self.meteringMode )
		{				
			case MeteringMode_Average: mmStr = @"average"; break;
			case MeteringMode_CenterWeight: mmStr = @"center weight"; break;
			case MeteringMode_Spot: mmStr = @"spot"; break;
			case MeteringMode_MultiSpot: mmStr = @"multi spot";  break;
			case MeteringMode_Pattern: mmStr = @"pattern"; break;
			case MeteringMode_Partial: mmStr = @"partial";  break;
			case MeteringMode_Other: mmStr = @"other";  break;
			default:
				mmStr = [NSString stringWithFormat:@"unknown (%d)", (unsigned)self.meteringMode];
				break;
        }
		[desc appendFormat:@"Metering Mode: %@\n", mmStr];
    }
	
    if ( self.exposureProgram != ExposureProgram_None )	// 05-jan-2001 vcs
	{
		NSString* epstr = nil;
        switch( self.exposureProgram )
		{
			case ExposureProgram_Manual:			epstr = @"Manual"; break;
			case ExposureProgram_Auto:				epstr = @"program (auto)"; break;
			case ExposureProgram_AperturePriority:	epstr = @"aperture priority (semi-auto)"; break;
			case ExposureProgram_ShutterPriority:	epstr = @"shutter priority (semi-auto)"; break;
			case ExposureProgram_Creative:			epstr = @"Creative Program (based towards depth of field)"; break;
			case ExposureProgram_Operation:			epstr = @"Operation program (based towards fast shutter speed)"; break;
			case ExposureProgram_Portrait:			epstr = @"Portrait Mode"; break;
			case ExposureProgram_Landscape:			epstr = @"Landscape Mode"; break;
			default:	 epstr = [NSString stringWithFormat:@"unknown (%d)", (unsigned)self.exposureProgram]; break;
        }
		[desc appendFormat:@"Exposure     : %@\n", epstr];
    }
	
	NSString* emStr = nil;
    switch ( self.exposureMode )
	{
        case ExposureMode_Automatic:		emStr = @"Automatic"; break;
        case ExposureMode_Manual:			emStr = @"Manual"; break;
        case ExposureMode_AutoBracketing:	emStr = @"Auto bracketing"; break;
		default: emStr = [NSString stringWithFormat:@"unknown (%d)", (unsigned)self.exposureMode]; break;
    }
	[desc appendFormat:@"Exposure Mode: %@\n", emStr];
	
    if ( self.distanceRange != DistanceRange_None )
	{
		NSString* drStr = NULL;
        switch(self.distanceRange)
		{
            case DistanceRange_Macro:	drStr = @"macro"; break;
            case DistanceRange_Close:	drStr = @"close"; break;
            case DistanceRange_Distant:	drStr = @"distant"; break;
			default: drStr = [NSString stringWithFormat:@"unknown (%d)", (unsigned)self.distanceRange]; break;
        }
		[desc appendFormat:@"Focus range  : %@\n", drStr];
    }
	
    if ( self.process != M_SOF0)
	{
			// don't show it if its the plain old boring 'baseline' process, but do
			// show it if its something else, like 'progressive' (used on web sometimes)
		[desc appendFormat:@"Jpeg process : %s\n", [JPEGManager processTableDesc:self.process]];
    }
	
    if ( self.gpsInfoPresent )
	{
        [desc appendFormat:@"GPS Latitude : %.2lfº\n", self.coordinate.latitude];		
        [desc appendFormat:@"GPS Longitude: %.2lfº\n", self.coordinate.longitude];
        [desc appendFormat:@"GPS Altitude : %.2lfm\n", self.altitude];
    }
	
		// Print the comment. Print 'Comment:' for each new line of comment.
    if ( self.comments )
	{
		[desc appendFormat:@"Comment      : %@\n", self.comments];
    }
	
	Section* IptcSection = [self findSection:M_IPTC];
	if ( IptcSection )
	{
		[self description_IPTC:IptcSection.data into:desc];
	}
	return desc;
}

-(NSData*)createJPEGData
{
	[self recreateEXIFSection];
	
	if ( _sections.count < 1 )
	{
		[[JPEGManagerException reason:@"Invalid JPEG file: no sections", nil] raise];
		return nil;
	}
	
    NSMutableData* outData = [[NSMutableData alloc] initWithLength:0];
	
	
	Section* firstSection = [_sections objectAtIndex:0];
	
		// Initial jpeg marker.
	uint8_t marker[2] = {
		0xff, M_SOI
	};
	[outData appendBytes:marker length:2];
    
	if ( firstSection.sectionType != M_EXIF && firstSection.sectionType != M_JFIF )
	{
			// The image must start with an exif or jfif marker.  If it doesn't have one,
			// write a JFIF section into the output.

        static uint8_t JfifHead[18] = {
            0xff, M_JFIF,
            0x00, 0x10, 'J' , 'F' , 'I' , 'F' , 0x00, 0x01, 
            0x01, 0x01, 0x01, 0x2C, 0x01, 0x2C, 0x00, 0x00 
        };
		
        if ( self.resolutionUnit == 2 || self.resolutionUnit == 3)
		{
				// Use the exif resolution info to fill out the jfif header.
				// Usually, for exif images, there's no jfif header, so if we discard
				// the exif header, use info from the exif header for the jfif header.
            
            self.JfifHeaderResolutionUnits = (char)(self.resolutionUnit-1);
				// Jfif is 1 and 2, Exif is 2 and 3 for In and cm respecively
            self.JfifHeaderXDensity = (int)self.xResolution;
            self.JfifHeaderYDensity = (int)self.yResolution;
        }
		
        JfifHead[11] = self.JfifHeaderResolutionUnits;
        JfifHead[12] = (uint8_t)(self.JfifHeaderXDensity >> 8);
        JfifHead[13] = (uint8_t)self.JfifHeaderXDensity;
        JfifHead[14] = (uint8_t)(self.JfifHeaderYDensity >> 8);
        JfifHead[15] = (uint8_t)self.JfifHeaderYDensity;
		
			// use the values from the exif data for the jfif header, if we have found values
        if (self.resolutionUnit != 0)
		{
				// JFIF.ResolutionUnit is {1,2}, EXIF.ResolutionUnit is {2,3}
            JfifHead[11] = (unsigned char)self.resolutionUnit - 1; 
        }
        if (self.xResolution > 0.0 && self.yResolution > 0.0)
		{ 
            JfifHead[12] = (unsigned char)((int)self.xResolution>>8);
            JfifHead[13] = (unsigned char)((int)self.xResolution);
			
            JfifHead[14] = (unsigned char)((int)self.yResolution>>8);
            JfifHead[15] = (unsigned char)((int)self.yResolution);
        }

		[outData appendBytes:JfifHead length:18];
    }
	
		// Write all but last sections to output
    for (Section* s in _sections)
	{				
		marker[1] = s.sectionType;

		NSLog(@"output section type: %lx", s.sectionType);

		[outData appendBytes:marker length:2];
		
		[outData appendData:s.data];
    }
	
	[outData appendData:_imageData];
	
		//marker[1] = M_EOI;
		//[outData appendBytes:marker length:2];
    return outData;
}

+(const char*)processTableDesc:(int)processType
{
	for (int a=0; a < PROCESS_TABLE_SIZE; a++)
	{
		if (ProcessTable[a].Tag == processType)
		{
			return ProcessTable[a].Desc;
		}
	}
	return "Unknown";
}


	//--------------------------------------------------------------------------
	// Process a EXIF marker
	// Describes all the drivel that most digital cameras include...
	//--------------------------------------------------------------------------
-(void)process_EXIF:(NSData*)exifData
{
	uint8_t* ExifSection = (uint8_t*)[exifData bytes];
	size_t length = exifData.length;
	
	ExifReader* exifReader = [[[ExifReader alloc] initWithJPEGMgr:self bytes:ExifSection length:length] autorelease];
	
	[exifReader read];
	
    if ( YES ) // debug output
	{
		NSMutableString* logStr = [NSMutableString stringWithCapacity:32];
        [logStr appendFormat:@"Map: %05d- End of exif\n", length-8];
        for (unsigned a=0;a<length-8;a+= 10)
		{
            [logStr appendFormat:@"Map: %05d ",a];
            for (unsigned b=0;b<10;b++) [logStr appendFormat:@" %02x",*(ExifSection+8+a+b)];
            [logStr appendString:@"\n"];
        }
		NSLog(@"process_EXIF:length::%@", logStr);
    }
	
	int wideDimension = _exifImageWidth > _exifImageLength ? _exifImageWidth : _exifImageLength;
	
		// Compute the CCD width, in millimeters.
    if (_focalplaneXRes != 0)
	{
			// Note: With some cameras, its not possible to compute this correctly because
			// they don't adjust the indicated focal plane resolution units when using less
			// than maximum resolution, so the CCDWidth value comes out too small.  Nothing
			// that Jhad can do about it - its a camera problem.
        self.CCDWidth = (float)(wideDimension * self.focalplaneUnits / self.focalplaneXRes);
		
        if (self.focalLength && self.focalLength35mmEquiv == 0)
		{
				// Compute 35 mm equivalent focal length based on sensor geometry if we haven't
				// already got it explicitly from a tag.
            self.focalLength35mmEquiv = (int)(self.focalLength/self.CCDWidth*36 + 0.5);
        }
    }
}

-(BOOL)has_EXIF
{
	return ( nil != [self findSection:M_EXIF] );
}

-(NSString*)currentDateString
{
	NSDateFormatter *outputFormatter = [[NSDateFormatter alloc] init];
	[outputFormatter setDateFormat:@"yyyy:MM:dd HH:mm:ss"];
	NSString* currentDate = [outputFormatter stringFromDate:[NSDate date]];
	[outputFormatter release];
	return currentDate;
}

-(void)recreateEXIFSection
{
	ExifWriter* exifWriter = [[[ExifWriter alloc] initWithBigEndianness:YES] autorelease];
	
		// Top level attributes: File mod date/time, links to sub dirs
	size_t entryOffset = [exifWriter declareDirectory:9];
	
		// [1]  File Date/time entry
	NSString* currentDate = [self currentDateString];
	[exifWriter putString:currentDate at:entryOffset entryNumber:0 tag:TAG_DATETIME];
		// [2]  Image Title/description			
	[exifWriter putString:self.imageDescription at:entryOffset entryNumber:1 tag:TAG_IMAGE_DESCRIPTION];
		// [3]
	[exifWriter putString:self.cameraMake at:entryOffset entryNumber:2 tag:TAG_MAKE];
		// [4]
	[exifWriter putString:self.cameraModel at:entryOffset entryNumber:3 tag:TAG_MODEL];
		// [5]
	[exifWriter putString:self.software at:entryOffset entryNumber:4 tag:TAG_SOFTWARE];
		// [6]
	[exifWriter putString:self.artist at:entryOffset entryNumber:5 tag:TAG_ARTIST];
		// [7]
	[exifWriter putString:self.copyright  at:entryOffset entryNumber:6 tag:TAG_COPYRIGHT];
	
		// [8] Link to JPEG dimensions dir
	size_t jpegDirEntryOffset = [exifWriter declareDirectoryAt:entryOffset entryNumber:7 tag:TAG_EXIF_OFFSET entriesCount:6];
	
		// [9] Link to GPS Info dir
	size_t gpsEntryOffset = [exifWriter declareDirectoryAt:entryOffset entryNumber:8 tag:TAG_GPSINFO entriesCount:6];
	
		// [-] Link to Thumbnail dir
		//	size_t thumbnailEntryOffset = [exifWriter declareDirectoryTag:TAG_EXIF_OFFSET entriesCount:2];
	
#if 1	// [8]  JPEG dimensions dir entry and image timestamps
	[exifWriter putEntryAt:jpegDirEntryOffset entryNumber:0 tag:TAG_COLOR_SPACE fmt:FMT_USHORT count:1 data:1<<16];
	[exifWriter putEntryAt:jpegDirEntryOffset entryNumber:1 tag:TAG_PIXEL_X_DIMENSION fmt:FMT_ULONG count:1 data:self.exifImageWidth];
	[exifWriter putEntryAt:jpegDirEntryOffset entryNumber:2 tag:TAG_PIXEL_Y_DIMENSION fmt:FMT_ULONG count:1 data:self.exifImageLength];
	
		// Original date/time entry
	[exifWriter putString:currentDate at:jpegDirEntryOffset entryNumber:3 tag:TAG_DATETIME_ORIGINAL];
	
		// date/time of digitization entry
	[exifWriter putString:currentDate at:jpegDirEntryOffset entryNumber:4 tag:TAG_DATETIME_DIGITIZED];
	
		// orientation of image
	[exifWriter putEntryAt:jpegDirEntryOffset entryNumber:5 tag:TAG_ORIENTATION fmt:FMT_USHORT count:1 data:UIImageOrientationToExifOrientation(self.orientation)];
#endif
	
#if 1 // entry [9]  GPS Info dir
	CoordinateTriple ct;
	unsigned char hemisphere = ' ';
	
	if ( self.coordinate.latitude < 0 )
	{
		hemisphere = 'S';
		ct = locationDegreesToCoordinateTriple(-self.coordinate.latitude);
	}
	else
	{
		hemisphere = 'N';
		ct = locationDegreesToCoordinateTriple(self.coordinate.latitude);
	}
	
	[exifWriter putChar:hemisphere at:gpsEntryOffset entryNumber:0 tag:TAG_GPS_LAT_REF];
	[exifWriter putCoordinateTriple:ct at:gpsEntryOffset entryNumber:1 tag:TAG_GPS_LAT];
	
	if ( self.coordinate.longitude < 0 )
	{
		hemisphere = 'W';
		ct = locationDegreesToCoordinateTriple(-self.coordinate.longitude);
	}
	else
	{
		hemisphere = 'E';
		ct = locationDegreesToCoordinateTriple(self.coordinate.longitude);
	}
	[exifWriter putChar:hemisphere at:gpsEntryOffset entryNumber:2 tag:TAG_GPS_LONG_REF];
	[exifWriter putCoordinateTriple:ct at:gpsEntryOffset entryNumber:3 tag:TAG_GPS_LONG];
	
	UInt32 altitudeRef = 0;
	URational altitudeR;
	if ( self.altitude < 0 )
	{
		altitudeRef = 1 << 24;
		altitudeR = doubleToURational(-self.altitude);
	}
	else 
	{
		altitudeR = doubleToURational(self.altitude);
	}
	[exifWriter putEntryAt:gpsEntryOffset entryNumber:4 tag:TAG_GPS_ALT_REF fmt:FMT_BYTE count:1 data:altitudeRef];
	[exifWriter putURational:altitudeR at:gpsEntryOffset entryNumber:5 tag:TAG_GPS_ALT];		
#endif
	
#if 0	// [--]  Thumbnail dir entry (not currently doing this)
	[exifWriter putOffsetEntryAt:thumbnailEntryOffset entryNumber:0 tag:TAG_THUMBNAIL_OFFSET];
	[exifWriter putEntryAt:thumbnailEntryOffset entryNumber:1 tag:TAG_THUMBNAIL_LENGTH fmt:FMT_ULONG count:1 data:0];
#endif	
	
		// Remove old exif section, if there was one.
    [self removeSectionType:M_EXIF];
	
	Section* exifSection = [[[Section alloc] initWithType:M_EXIF data:[exifWriter serialize]] autorelease];	
	[self addExifSection:exifSection];
	
		// Re-parse new exif section, now that it's in place
		// otherwise, we risk touching data that was freed when we removed the old M_EXIF section just now.
		// actually, this is probably not necessary, but remains as a sanity check on the validity of our EXIF-generation
	[self process_EXIF:exifSection.data];
}

	//--------------------------------------------------------------------------
	// Add a section (assume it doesn't already exist) - used for 
	// adding comment sections and exif sections
	//--------------------------------------------------------------------------
-(void)addSection:(Section*)section
{
	[_sections addObject:section];
}

-(void)addExifSection:(Section*)section
{
	[_sections insertObject:section atIndex:0];
}

-(void)addCommentSection:(Section*)section
{
	if ( _sections.count >= 2 )
		[_sections insertObject:section atIndex:2];
	else 
		[_sections addObject:section];
}

	//--------------------------------------------------------------------------
	// Process a COM marker.
	// We want to print out the marker contents as legible text;
	// we must guard against random junk and varying newline representations.
	//--------------------------------------------------------------------------
-(void)process_COM:(NSData*)sectionData
{	
    if (sectionData.length > MAX_COMMENT_SIZE)
		[[JPEGManagerException reason:@"size of comment section is larger than allowed", nil] raise];
	

	self.comments = [[[NSString alloc] initWithBytes:[sectionData bytes]+2 length:sectionData.length-2 encoding:NSASCIIStringEncoding] autorelease];
}


	//--------------------------------------------------------------------------
	// Process a SOFn marker.  This is useful for the image dimensions
	//--------------------------------------------------------------------------
-(void)process_SOFn:(NSData*)sectionData marker:(JPEGMarker_t)marker
{
	uint8_t* data = (uint8_t*)[sectionData bytes];
    int data_precision = data[2];
    self.height = Get16m(data+3);
    self.width = Get16m(data+5);
	
    int num_components = data[7];
	self.isColor = num_components == 3;
    self.process = marker;
	
	NSLog(@"JPEG image is %uw * %uh, %d color components, %d bits per sample",
			  self.width, self.height, num_components, data_precision);
}

	//--------------------------------------------------------------------------
	// Parse the marker stream until SOS or EOI is seen;
	//--------------------------------------------------------------------------
-(void)readJpegSections:(NSData*)jpegData
{
	uint8_t* jpegbytes = (uint8_t*) [jpegData bytes];
	uint8_t* eof = jpegbytes + jpegData.length;
	
	uint8_t firstByte = *jpegbytes++;
	uint8_t secondByte = *jpegbytes++;
	uint8_t* lastMarker = eof-2;
	
	if ( firstByte != 0xff || secondByte != M_SOI || (lastMarker[0] != 0xff && lastMarker[1] != M_EOI) )
	{
		[[JPEGManagerException reason:@"Not valid JPEG file data", nil] raise];
	}
		
    self.JfifHeaderXDensity = self.JfifHeaderYDensity = 300;
    self.JfifHeaderResolutionUnits = 1;
		
    for(;;)
	{
		uint8_t ffflag = *jpegbytes++;
		JPEGMarker_t marker = *jpegbytes++;
		
		if ( !(ffflag == 0xff && marker != 0xff) )
		{
				// image data starting; last two bytes ought to be 0xFF M_EOI, which we leave on the end of the JPEG data.
				// The entire remainder of the file is the image data, so we're done.
			
			jpegbytes -= 2;
			_imageData = [[NSData dataWithBytesNoCopy:jpegbytes length:eof-jpegbytes freeWhenDone:NO] retain];
			return;
		}
			// else, this is the start of a marked section
		
		uint8_t* dataStart = jpegbytes;
		
			// Read the length of the section.
        uint16_t lh = *jpegbytes++;
        uint16_t ll = *jpegbytes++;
        size_t itemlen = (lh << 8) | ll;
		
        if (itemlen < 2)
		{
			[[JPEGManagerException reason:@"JPEG section has invalid too-short length in header", nil] raise];
        }
		
		int toRead = itemlen - 2;
		if ( jpegbytes + toRead > eof )
		{
			[[JPEGManagerException reason:@"JPEG section has invalid too-long length in header", nil] raise];
        }
		jpegbytes += toRead;
		
        switch(marker)
		{
			case M_SOS: 
				if (YES)
				{
					NSLog(@"Input Section SOS dataStart %lx, len %lu", dataStart, itemlen);
					Section* section = [[Section alloc] initWithType:M_SOS bytes:dataStart length:itemlen];
					[self addSection:section];
					[section release];
				}
				break;
				
            case M_EOI:   // in case it's a tables-only JPEG stream
				[[JPEGManagerException reason:@"JPEG data does not appear to contain an image", nil] raise];
				break;
				
            case M_COM: // Comment section
				if (YES)
				{
					NSLog(@"Input Section COM dataStart %lx, len %lu", dataStart, itemlen);
					Section* section = [[Section alloc] initWithType:M_COM bytes:dataStart length:itemlen];
					[self addSection:section];
					[self process_COM:section.data];
					[section release];
				}
                break;
				
            case M_JFIF:
				NSLog(@"Input section JFIF dataStart %lx, len %lu", dataStart, itemlen);
					// Regular jpegs always have this tag, exif images have the exif
					// marker instead, althogh ACDsee will write images with both markers.
					// this program will re-create this marker on absence of exif marker.
					// hence no need to keep the copy from the file.
                if (memcmp(dataStart+2, "JFIF\0",5))
				{
                    NSLog(@"Header missing JFIF marker");
                }
                if (itemlen < 16)
				{
                    NSLog(@"Jfif header too short");
                }
				else 
				{
					self.JfifHeaderPresent = TRUE;
					self.JfifHeaderResolutionUnits = dataStart[9];
					self.JfifHeaderXDensity = (dataStart[10]<<8) | dataStart[11];
					self.JfifHeaderYDensity = (dataStart[12]<<8) | dataStart[13];
					
					if ( YES )
					{
						NSLog(@"JFIF SOI marker: Units: %d ",self.JfifHeaderResolutionUnits);
						switch(self.JfifHeaderResolutionUnits)
						{
							case 0: NSLog(@"   (aspect ratio)"); break;
							case 1: NSLog(@"   (dots per inch)"); break;
							case 2: NSLog(@"   (dots per cm)"); break;
							default: NSLog(@"   (unknown)"); break;
						}
						NSLog(@"      X-density=%d Y-density=%d\n",self.JfifHeaderXDensity, self.JfifHeaderYDensity);
						
						if ( dataStart[14] || dataStart[15] )
						{
							NSLog(@"Ignoring jfif header thumbnail");
						}
					}
				}
                break;
				
            case M_EXIF:
				NSLog(@"Input Section EXIF dataStart %lx, len %lu", dataStart, itemlen);
				if (memcmp(dataStart+2, "Exif", 4) == 0)
				{
					NSLog(@"   Normal EXIF");
					Section* section = nil;
					@try {
						section = [[Section alloc] initWithType:M_EXIF bytes:dataStart length:itemlen];
						[self addSection:section];
						[self process_EXIF:section.data];
					}
					@finally
					{
						[section release];
					}
					break;
				}
				else if (memcmp(dataStart+2, "http:", 5) == 0)
				{
					NSLog(@"   URL-style EXIF, treating as XMP");
						// Change tag for internal purposes
					Section* section = [[Section alloc] initWithType:M_XMP bytes:dataStart length:itemlen];
					[self addSection:section];
					[section release];
					break;
				}
                break;
				
            case M_IPTC:
				if (YES)
				{
					NSLog(@"Input Section IPTC dataStart %lx, len %lu", dataStart, itemlen);
					Section* section = [[Section alloc] initWithType:M_IPTC bytes:dataStart length:itemlen];
					[self addSection:section];
					[section release];
				}
                break;
				
            case M_SOF0: 
            case M_SOF1: 
            case M_SOF2: 
            case M_SOF3: 
            case M_SOF5: 
            case M_SOF6: 
            case M_SOF7: 
            case M_SOF9: 
            case M_SOF10:
            case M_SOF11:
            case M_SOF13:
            case M_SOF14:
            case M_SOF15:
				if (YES)
				{
					NSLog(@"Input Section M_SOFx (0x%02x) dataStart %lx, len %lu", marker, dataStart, itemlen);
					Section* section = [[Section alloc] initWithType:marker bytes:dataStart length:itemlen];
					[self addSection:section];
					[self process_SOFn:section.data marker:marker];
					[section release];
				}
                break;
				
            default:
					// Skip any other sections.
				if (YES)
				{
					NSLog(@"Input Section (0x%02x) dataStart %lx, len %lu", marker, dataStart, itemlen);
					Section* section = [[Section alloc] initWithType:marker bytes:dataStart length:itemlen];
					[self addSection:section];
					[section release];
				}
                break;
        }
    }
}

	//TODO: support including thumbnail images in the output EXIF section
-(NSData*)thumbnail
{
	return _thumbnail;
}

-(void)setThumbnail:(NSData*)v
{
	[_thumbnail release];

	if ( nil == v || v.length == 0 )
	{
		_thumbnail = nil;
	}
	else
	{
		_thumbnail = [v retain];
	}
}

	//--------------------------------------------------------------------------
	// Check if image has exif header.
	//--------------------------------------------------------------------------
-(Section*)findSection:(JPEGMarker_t)SectionType
{
	for (Section* s in _sections)
	{
		if ( s.sectionType == SectionType )
			return s;
	}
	return nil;
}

	//--------------------------------------------------------------------------
	// Remove a certain type of section.
	//--------------------------------------------------------------------------
-(BOOL)removeSectionType:(JPEGMarker_t)SectionType
{
	NSMutableIndexSet* indices = [NSMutableIndexSet indexSet];
	NSUInteger removals = 0;
	NSUInteger currentIndex = 0;
	
	for (Section* s in _sections)
	{
		if ( s.sectionType == SectionType )
		{
			removals++;
			[indices addIndex:currentIndex];
		}
		currentIndex++;
	}

	[_sections removeObjectsAtIndexes:indices];
    return removals > 0;
}

-(void)removeSection:(Section*)s
{
	[_sections removeObjectIdenticalTo:s];
}

	//--------------------------------------------------------------------------
	// Remove sectons not part of image and not exif or comment sections.
	//--------------------------------------------------------------------------
-(BOOL)removeUnknownSections
{
	NSMutableIndexSet* indices = [NSMutableIndexSet indexSet];
	NSUInteger currentIndex = 0;
    BOOL modified = FALSE;
	
    for ( Section* s in _sections )
	{
		if ( currentIndex == _sections.count - 1 ) break; // don't remove the last one
		
        switch( s.sectionType )
		{
            case  M_SOF0:
            case  M_SOF1:
            case  M_SOF2:
            case  M_SOF3:
            case  M_SOF5:
            case  M_SOF6:
            case  M_SOF7:
            case  M_SOF9:
            case  M_SOF10:
            case  M_SOF11:
            case  M_SOF13:
            case  M_SOF14:
            case  M_SOF15:
            case  M_SOI:
            case  M_EOI:
            case  M_SOS:
            case  M_JFIF:
            case  M_EXIF:
            case  M_XMP:
            case  M_COM:
            case  M_DQT:
            case  M_DHT:
            case  M_DRI:
            case  M_IPTC:
					// keep.
                break;
            default:
					// Unknown.  Delete.
				[indices addIndex:currentIndex];
                modified = TRUE;
        }
		currentIndex++;
    }
	
	[_sections removeObjectsAtIndexes:indices];
    return modified;
}

#pragma mark -

	//--------------------------------------------------------------------------
	//  Process and display IPTC marker.
	//
	//  IPTC block consists of:
	//      - Marker:               1 byte      (0xED)
	//      - Block length:         2 bytes
	//      - IPTC Signature:       14 bytes    ("Photoshop 3.0\0")
	//      - 8BIM Signature        4 bytes     ("8BIM")
	//      - IPTC Block start      2 bytes     (0x04, 0x04)
	//      - IPTC Header length    1 byte
	//      - IPTC header           Header is padded to even length, counting the length byte
	//      - Length                4 bytes
	//      - IPTC Data which consists of a number of entries, each of which has the following format:
	//              - Signature     2 bytes     (0x1C02)
	//              - Entry type    1 byte      (for defined entry types, see #defines above)
	//              - entry length  2 bytes
	//              - entry data    'entry length' bytes
	//
	//--------------------------------------------------------------------------
-(void)description_IPTC:(NSData*)sectionData into:(NSMutableString*)desc
{
    const char IptcSig1[] = "Photoshop 3.0";
    const char IptcSig2[] = "8BIM";
    const char IptcSig3[] = {0x04, 0x04};
	
	NSUInteger itemlen = sectionData.length;
	
	uint8_t* start = (uint8_t*)[sectionData bytes];
	uint8_t* pos = start + sizeof(short);	// position data pointer after length field
    uint8_t* maxpos = start + itemlen;
	uint8_t* endOfIPTC =  start + itemlen - 5;
	
    char  headerLen = 0;
	
    if (itemlen < 25) goto corrupt;
	
		// Check IPTC signatures
    if (memcmp(pos, IptcSig1, sizeof(IptcSig1)-1) != 0) goto badsig;
    pos += sizeof(IptcSig1);      // move data pointer to the next field
	
    if (memcmp(pos, IptcSig2, sizeof(IptcSig2)-1) != 0) goto badsig;
    pos += sizeof(IptcSig2)-1;          // move data pointer to the next field
	
    if (memcmp(pos, IptcSig3, sizeof(IptcSig3)) != 0)
	{
	badsig:
		[[JPEGManagerException reason:@"IPTC type signature mismatch", nil] raise];
    }
    pos += sizeof(IptcSig3);          // move data pointer to the next field
	
    if (pos >= maxpos) goto corrupt;
	
		// IPTC section found
	
		// Skip header
    headerLen = *pos++;                     // get header length and move data pointer to the next field
    pos += headerLen + 1 - (headerLen % 2); // move data pointer to the next field (Header is padded to even length, counting the length byte)
	
    if (pos+4 >= maxpos) goto corrupt;
	
		// Get length (from motorola format)
		//length = (*pos << 24) | (*(pos+1) << 16) | (*(pos+2) << 8) | *(pos+3);
	
    pos += 4;                    // move data pointer to the next field
		
		// Now read IPTC data
    while ( pos < endOfIPTC )
	{
        short  signature;
        unsigned char   type = 0;
        short  length = 0;
        char * description = NULL;
		
        if (pos+5 > maxpos) goto corrupt;
		
        signature = (*pos << 8) + (*(pos+1));
        pos += 2;
		
        if (signature != 0x1C02)
		{
            break;
        }
		
        type    = *pos++;
        length  = (*pos << 8) + (*(pos+1));
        pos    += 2;                          // Skip tag length
		
        if (pos+length > maxpos) goto corrupt;
			// Process tag here
        switch (type)
		{
            case IPTC_RECORD_VERSION:
                [desc appendFormat:@"Record vers.  : %d\n", (*pos << 8) + (*(pos+1))];
                break;
				
            case IPTC_SUPLEMENTAL_CATEGORIES:  description = "SuplementalCategories"; break;
            case IPTC_KEYWORDS:                description = "Keywords"; break;
            case IPTC_CAPTION:                 description = "Caption"; break;
            case IPTC_AUTHOR:                  description = "Author"; break;
            case IPTC_HEADLINE:                description = "Headline"; break;
            case IPTC_SPECIAL_INSTRUCTIONS:    description = "Spec. Instr."; break;
            case IPTC_CATEGORY:                description = "Category"; break;
            case IPTC_BYLINE:                  description = "Byline"; break;
            case IPTC_BYLINE_TITLE:            description = "Byline Title"; break;
            case IPTC_CREDIT:                  description = "Credit"; break;
            case IPTC_SOURCE:                  description = "Source"; break;
            case IPTC_COPYRIGHT_NOTICE:        description = "(C)Notice"; break;
            case IPTC_OBJECT_NAME:             description = "Object Name"; break;
            case IPTC_CITY:                    description = "City"; break;
            case IPTC_STATE:                   description = "State"; break;
            case IPTC_COUNTRY:                 description = "Country"; break;
            case IPTC_TRANSMISSION_REFERENCE:  description = "OriginalTransmissionReference"; break;
            case IPTC_DATE:                    description = "DateCreated"; break;
            case IPTC_COPYRIGHT:               description = "(C)Flag"; break;
            case IPTC_REFERENCE_SERVICE:       description = "Country Code"; break;
            case IPTC_COUNTRY_CODE:            description = "Ref. Service"; break;
            case IPTC_TIME_CREATED:            description = "Time Created"; break;
            case IPTC_SUB_LOCATION:            description = "Sub Location"; break;
            case IPTC_IMAGE_TYPE:              description = "Image type"; break;
				
            default:
				[desc appendFormat:@"Unrecognised IPTC tag: %d\n", type];
				break;
        }
        if (description != NULL)
		{
            char TempBuf[32];
            memset(TempBuf, 0, sizeof(TempBuf));
            memset(TempBuf, ' ', 14);
            memcpy(TempBuf, description, strlen(description));
            strcat(TempBuf, ":"); 
            [desc appendFormat:@"%s %*.*s\n", TempBuf, length, length, pos];
        }
        pos += length;
    }
    return;
corrupt:
	[[JPEGManagerException reason:@"Pointer corruption in IPTC", nil] raise];
}


@end

