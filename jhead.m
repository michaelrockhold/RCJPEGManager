//--------------------------------------------------------------------------
// Program to pull the information out of various types of EXIF digital 
// camera files and show it in a reasonably consistent way
//
// Version 2.88
//
// Dec 1999 - Nov 2009
//
// by Matthias Wandel   www.sentex.net/~mwandel
//--------------------------------------------------------------------------
#import "jhead.h"
#import "TagTable.h"
#import "JPEGManagerException.h"

#define JHEAD_VERSION "2.88"

unsigned char * dir_entry_address(unsigned char * start, int entry)
{
	return start + 2 + 12* entry;
}

//--------------------------------------------------------------------------

URational makeURational(UInt32 numerator, UInt32 denominator)
{
	URational ur;
	ur.numerator = numerator; ur.denominator = denominator;
	return ur;
}

SRational makeSRational(SInt32 numerator, SInt32 denominator)
{
	SRational sr;
	sr.numerator = numerator; sr.denominator = denominator;
	return sr;
}

double urationalToDouble(URational ur)
{
	return ((double)ur.numerator) / ur.denominator;
}

URational doubleToURational(double d)
{
	const UInt32 MAX_DENOM = 0xFFFF;

	URational ur = makeURational(floor(d), 1);
	
    UInt32 p0 = 1;
    UInt32 q0 = 0;
    UInt32 p2;
    UInt32 q2;

    double r = d - ur.numerator;
    double next_cf;
    while ( r != 0 )
    {
        r = 1.0 / r;
        next_cf = floor(r);
        p2 = (UInt32)(next_cf * ur.numerator + p0);
        q2 = (UInt32)(next_cf * ur.denominator + q0);

        // Limit the numerator and denominator to be 256 or less
        if ( p2 > MAX_DENOM || q2 > MAX_DENOM )
                break;

        // remember the last two fractions
        p0 = ur.numerator;
        ur.numerator = p2;
        q0 = ur.denominator;
        ur.denominator = q2;

        r -= next_cf;
    }

    d = (double) ur.numerator / ur.denominator;
    // hard upper and lower bounds for ratio
    if ( d > MAX_DENOM )
    {
		ur = makeURational(MAX_DENOM, 1);
    }
    else if ( d < 1.0 / MAX_DENOM )
    {
		ur = makeURational(1, MAX_DENOM);
    }
    return ur;
}

double srationalToDouble(SRational sr)
{
	return ((double)sr.numerator) / sr.denominator;
}

CoordinateTriple locationDegreesToCoordinateTriple(CLLocationDegrees ld)
{
	CoordinateTriple dest;
	
	UInt32 degrees = floor(ld);
	dest.degrees = makeURational(degrees, 1);
	
	ld = (ld - degrees) * 60;
	UInt32 minutes = floor(ld);
	dest.minutes = makeURational(minutes, 1);
	
	ld = (ld - minutes) * 60;
	dest.seconds = doubleToURational(ld);
	
	return dest;
}

CLLocationDegrees coordinateTripleToLocationDegrees(CoordinateTriple ct)
{
	CLLocationDegrees dest;
	
	dest = ct.degrees.numerator / ct.degrees.denominator;
	
	dest += (ct.minutes.numerator / ct.degrees.denominator / 60);
	
	dest += (ct.seconds.numerator / ct.seconds.denominator / 60);
	
	return dest;
}

uint8_t*
put16u(uint8_t* dst, BOOL bigEndian, uint16_t putValue)
{
    if ( bigEndian )
	{
        dst[0] = (uint8_t)(putValue>>8);
        dst[1] = (uint8_t)putValue;
    }
	else
	{
        dst[0] = (uint8_t)putValue;
        dst[1] = (uint8_t)(putValue>>8);
    }
	return dst+2;	
}

uint8_t*
put32u(uint8_t* dst, BOOL bigEndian, uint32_t ui)
{
    if ( bigEndian )
	{
        dst[0] = (uint8_t)(ui>>24);
        dst[1] = (uint8_t)(ui>>16);
        dst[2] = (uint8_t)(ui>>8);
        dst[3] = (uint8_t)ui;
    }
	else
	{
        dst[0] = (uint8_t)ui;
        dst[1] = (uint8_t)(ui>>8);
        dst[2] = (uint8_t)(ui>>16);
        dst[3] = (uint8_t)(ui>>24);
    }
	return dst+4;
}

uint16_t get16u(uint8_t* bytes, BOOL bigEndian)
{
	return bigEndian ? ((bytes[0] << 8) | bytes[1]) : ((bytes[1] << 8) | bytes[0]);
}

int32_t get32s(uint8_t* bytes, BOOL bigEndian)
{
    if ( bigEndian )
	{
        return  (bytes[0] << 24) | (bytes[1] << 16)
		| (bytes[2] << 8 ) | (bytes[3] << 0 );
    }
	else
	{
        return  (bytes[3] << 24) | (bytes[2] << 16)
		| (bytes[1] << 8 ) | (bytes[0] << 0 );
    }
}

uint32_t get32u(uint8_t* bytes, BOOL bigEndian)
{
    return (uint32_t)get32s(bytes, bigEndian) & 0xffffffff;
}


URational getURational(uint8_t* bytes, BOOL bigEndian)
{
	URational ur;
	ur.numerator = get32u(bytes, bigEndian);
	ur.denominator = get32u(bytes + sizeof(uint32_t), bigEndian);
	return ur;
}

SRational getSRational(uint8_t* bytes, BOOL bigEndian)
{
	SRational sr;
	sr.numerator = get32s(bytes, bigEndian);
	sr.denominator = get32s(bytes+sizeof(int32_t), bigEndian);
	return sr;
}

CoordinateTriple getCoordinateTriple(uint8_t* bytes, BOOL bigEndian)
{
	CoordinateTriple ct;
	ct.degrees = getURational(bytes, bigEndian); bytes += sizeof(uint32_t) * 2;
	ct.minutes = getURational(bytes, bigEndian); bytes += sizeof(uint32_t) * 2;
	ct.seconds = getURational(bytes, bigEndian);
	return ct;
}

	//--------------------------------------------------------------------------
	// Display a number as one of its many formats
	//--------------------------------------------------------------------------
NSString*
NumberValue(uint8_t* ValuePtr, JPEGNumberFormat_t format, NSUInteger ByteCount, BOOL bigEndian)
{
    int s,n;
	NSMutableString* logStr = [NSMutableString stringWithCapacity:32];
	
    for(n=0;n<16;n++)
	{
        switch(format)
		{
            case FMT_SBYTE:
            case FMT_BYTE:      [logStr appendFormat:@"%02x",*(unsigned char *)ValuePtr]; s=1;  break;
            case FMT_USHORT:    [logStr appendFormat:@"%u", get16u(ValuePtr, bigEndian)]; s=2;      break;
            case FMT_SSHORT:    [logStr appendFormat:@"%hd",(signed short)get16u(ValuePtr, bigEndian)]; s=2; break;
            case FMT_ULONG:     [logStr appendFormat:@"%lu", get32u(ValuePtr, bigEndian)]; s=4;      break;
            case FMT_SLONG:     [logStr appendFormat:@"%ld", get32s(ValuePtr, bigEndian)]; s=4;      break;
            case FMT_URATIONAL:
				[logStr appendFormat:@"%lu/%lu", get32u(ValuePtr, bigEndian), get32u(ValuePtr+4, bigEndian)]; 
				s = 8;
				break;
            case FMT_SRATIONAL: 
				[logStr appendFormat:@"%ld/%ld",get32s(ValuePtr, bigEndian), get32s(ValuePtr+4, bigEndian)]; 
				s = 8;
				break;
				
            case FMT_SINGLE:    [logStr appendFormat:@"%f",(double)*(float *)ValuePtr]; s=8; break;
            case FMT_DOUBLE:    [logStr appendFormat:@"%f",*(double *)ValuePtr];        s=8; break;
            default: 
                [logStr appendFormat:@"Unknown format %d:", format];
                return logStr;
        }
        ByteCount -= s;
        if (ByteCount <= 0) break;
        [logStr appendString:@", "];
        ValuePtr = (void *)((char *)ValuePtr + s);
    }
    if (n >= 16) [logStr appendString:@"..."];
	return logStr;
}


	//--------------------------------------------------------------------------
	// Evaluate number, be it int, rational, or float from directory.
	//--------------------------------------------------------------------------
double
ConvertAny(uint8_t* ValuePtr, JPEGNumberFormat_t format, BOOL bigEndian)
{
    double Value;
    Value = 0;
	
    switch(format){
        case FMT_SBYTE:     Value = *(signed char *)ValuePtr;  break;
        case FMT_BYTE:      Value = *(unsigned char *)ValuePtr;        break;
			
        case FMT_USHORT:    Value = get16u(ValuePtr, bigEndian);          break;
        case FMT_ULONG:     Value = get32u(ValuePtr, bigEndian);          break;
			
        case FMT_URATIONAL:
        case FMT_SRATIONAL: 
		{
			int Num,Den;
			Num = get32s(ValuePtr, bigEndian);
			Den = get32s(ValuePtr+4, bigEndian);
			if (Den == 0)
			{
				Value = 0;
			}
			else
			{
				Value = (double)Num/Den;
			}
			break;
		}
			
        case FMT_SSHORT:    Value = (signed short)get16u(ValuePtr, bigEndian);  break;
        case FMT_SLONG:     Value = get32s(ValuePtr, bigEndian);                break;
			
				// Not sure if this is correct (never seen float used in Exif format)
        case FMT_SINGLE:    Value = (double)*(float *)ValuePtr;      break;
        case FMT_DOUBLE:    Value = *(double *)ValuePtr;             break;
			
        default:
            [[JPEGManagerException reason:@"Illegal format code %@ in EXIF header", [NSNumber numberWithInt:format]] raise];
			break;
	}
    return Value;
}

#pragma mark -
const TagTable_t TagTable[] = {
	{ TAG_INTEROP_INDEX,          "InteropIndex"},
	{ TAG_INTEROP_VERSION,        "InteropVersion"},
	{ TAG_IMAGE_WIDTH,            "ImageWidth"},
	{ TAG_IMAGE_LENGTH,           "ImageLength"},
	{ TAG_BITS_PER_SAMPLE,        "BitsPerSample"},
	{ TAG_COMPRESSION,            "Compression"},
	{ TAG_PHOTOMETRIC_INTERP,     "PhotometricInterpretation"},
	{ TAG_FILL_ORDER,             "FillOrder"},
	{ TAG_DOCUMENT_NAME,          "DocumentName"},
	{ TAG_IMAGE_DESCRIPTION,      "ImageDescription"},
	{ TAG_MAKE,                   "Make"},
	{ TAG_MODEL,                  "Model"},
	{ TAG_SRIP_OFFSET,            "StripOffsets"},
	{ TAG_ORIENTATION,            "Orientation"},
	{ TAG_SAMPLES_PER_PIXEL,      "SamplesPerPixel"},
	{ TAG_ROWS_PER_STRIP,         "RowsPerStrip"},
	{ TAG_STRIP_BYTE_COUNTS,      "StripByteCounts"},
	{ TAG_X_RESOLUTION,           "XResolution"},
	{ TAG_Y_RESOLUTION,           "YResolution"},
	{ TAG_PLANAR_CONFIGURATION,   "PlanarConfiguration"},
	{ TAG_RESOLUTION_UNIT,        "ResolutionUnit"},
	{ TAG_TRANSFER_FUNCTION,      "TransferFunction"},
	{ TAG_SOFTWARE,               "Software"},
	{ TAG_DATETIME,               "DateTime"},
	{ TAG_ARTIST,                 "Artist"},
	{ TAG_WHITE_POINT,            "WhitePoint"},
	{ TAG_PRIMARY_CHROMATICITIES, "PrimaryChromaticities"},
	{ TAG_TRANSFER_RANGE,         "TransferRange"},
	{ TAG_JPEG_PROC,              "JPEGProc"},
	{ TAG_THUMBNAIL_OFFSET,       "ThumbnailOffset"},
	{ TAG_THUMBNAIL_LENGTH,       "ThumbnailLength"},
	{ TAG_Y_CB_CR_COEFFICIENTS,   "YCbCrCoefficients"},
	{ TAG_Y_CB_CR_SUB_SAMPLING,   "YCbCrSubSampling"},
	{ TAG_Y_CB_CR_POSITIONING,    "YCbCrPositioning"},
	{ TAG_REFERENCE_BLACK_WHITE,  "ReferenceBlackWhite"},
	{ TAG_RELATED_IMAGE_WIDTH,    "RelatedImageWidth"},
	{ TAG_RELATED_IMAGE_LENGTH,   "RelatedImageLength"},
	{ TAG_CFA_REPEAT_PATTERN_DIM, "CFARepeatPatternDim"},
	{ TAG_CFA_PATTERN1,           "CFAPattern"},
	{ TAG_BATTERY_LEVEL,          "BatteryLevel"},
	{ TAG_COPYRIGHT,              "Copyright"},
	{ TAG_EXPOSURETIME,           "ExposureTime"},
	{ TAG_FNUMBER,                "FNumber"},
	{ TAG_IPTC_NAA,               "IPTC/NAA"},
	{ TAG_EXIF_OFFSET,            "ExifOffset"},
	{ TAG_INTER_COLOR_PROFILE,    "InterColorProfile"},
	{ TAG_EXPOSURE_PROGRAM,       "ExposureProgram"},
	{ TAG_SPECTRAL_SENSITIVITY,   "SpectralSensitivity"},
	{ TAG_GPSINFO,                "GPS Dir offset"},
	{ TAG_ISO_EQUIVALENT,         "ISOSpeedRatings"},
	{ TAG_OECF,                   "OECF"},
	{ TAG_EXIF_VERSION,           "ExifVersion"},
	{ TAG_DATETIME_ORIGINAL,      "DateTimeOriginal"},
	{ TAG_DATETIME_DIGITIZED,     "DateTimeDigitized"},
	{ TAG_COMPONENTS_CONFIG,      "ComponentsConfiguration"},
	{ TAG_CPRS_BITS_PER_PIXEL,    "CompressedBitsPerPixel"},
	{ TAG_SHUTTERSPEED,           "ShutterSpeedValue"},
	{ TAG_APERTURE,               "ApertureValue"},
	{ TAG_BRIGHTNESS_VALUE,       "BrightnessValue"},
	{ TAG_EXPOSURE_BIAS,          "ExposureBiasValue"},
	{ TAG_MAXAPERTURE,            "MaxApertureValue"},
	{ TAG_SUBJECT_DISTANCE,       "SubjectDistance"},
	{ TAG_METERING_MODE,          "MeteringMode"},
	{ TAG_LIGHT_SOURCE,           "LightSource"},
	{ TAG_FLASH,                  "Flash"},
	{ TAG_FOCALLENGTH,            "FocalLength"},
	{ TAG_MAKER_NOTE,             "MakerNote"},
	{ TAG_USERCOMMENT,            "UserComment"},
	{ TAG_SUBSEC_TIME,            "SubSecTime"},
	{ TAG_SUBSEC_TIME_ORIG,       "SubSecTimeOriginal"},
	{ TAG_SUBSEC_TIME_DIG,        "SubSecTimeDigitized"},
	{ TAG_WINXP_TITLE,            "Windows-XP Title"},
	{ TAG_WINXP_COMMENT,          "Windows-XP comment"},
	{ TAG_WINXP_AUTHOR,           "Windows-XP author"},
	{ TAG_WINXP_KEYWORDS,         "Windows-XP keywords"},
	{ TAG_WINXP_SUBJECT,          "Windows-XP subject"},
	{ TAG_FLASH_PIX_VERSION,      "FlashPixVersion"},
	{ TAG_COLOR_SPACE,            "ColorSpace"},
	{ TAG_PIXEL_X_DIMENSION,      "ExifImageWidth"},
	{ TAG_PIXEL_Y_DIMENSION,      "ExifImageLength"},
	{ TAG_RELATED_AUDIO_FILE,     "RelatedAudioFile"},
	{ TAG_INTEROP_OFFSET,         "InteroperabilityOffset"},
	{ TAG_FLASH_ENERGY,           "FlashEnergy"},              
	{ TAG_SPATIAL_FREQ_RESP,      "SpatialFrequencyResponse"}, 
	{ TAG_FOCAL_PLANE_XRES,       "FocalPlaneXResolution"},    
	{ TAG_FOCAL_PLANE_YRES,       "FocalPlaneYResolution"},    
	{ TAG_FOCAL_PLANE_UNITS,      "FocalPlaneResolutionUnit"}, 
	{ TAG_SUBJECT_LOCATION,       "SubjectLocation"},          
	{ TAG_EXPOSURE_INDEX,         "ExposureIndex"},            
	{ TAG_SENSING_METHOD,         "SensingMethod"},            
	{ TAG_FILE_SOURCE,            "FileSource"},
	{ TAG_SCENE_TYPE,             "SceneType"},
	{ TAG_CFA_PATTERN,            "CFA Pattern"},
	{ TAG_CUSTOM_RENDERED,        "CustomRendered"},
	{ TAG_EXPOSURE_MODE,          "ExposureMode"},
	{ TAG_WHITEBALANCE,           "WhiteBalance"},
	{ TAG_DIGITALZOOMRATIO,       "DigitalZoomRatio"},
	{ TAG_FOCALLENGTH_35MM,       "FocalLengthIn35mmFilm"},
	{ TAG_SUBJECTAREA,            "SubjectArea"},
	{ TAG_SCENE_CAPTURE_TYPE,     "SceneCaptureType"},
	{ TAG_GAIN_CONTROL,           "GainControl"},
	{ TAG_CONTRAST,               "Contrast"},
	{ TAG_SATURATION,             "Saturation"},
	{ TAG_SHARPNESS,              "Sharpness"},
	{ TAG_DISTANCE_RANGE,         "SubjectDistanceRange"},
	{ TAG_IMAGE_UNIQUE_ID,        "ImageUniqueId"},
} ;

#define TAG_TABLE_SIZE  (sizeof(TagTable) / sizeof(TagTable_t))

char*
TagName(int tag)
{
	for (int a=0; a < TAG_TABLE_SIZE; a++)
	{
		if ( TagTable[a].Tag == tag )
		{
			return TagTable[a].Desc;
		}
	}
	return NULL;
}
