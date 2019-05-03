//--------------------------------------------------------------------------
// Include file for jhead program.
//
// This include file only defines stuff that goes across modules.  
// I like to keep the definitions for macros and structures as close to 
// where they get used as possible, so include files only get stuff that 
// gets used in more than one file.
//--------------------------------------------------------------------------

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

#define MAX_COMMENT_SIZE 2000

	//--------------------------------------------------------------------------
	// JPEG markers consist of one or more 0xFF bytes, followed by a marker
	// code byte (which is not an FF).  Here are the marker codes of interest
	// in this program.  (See jdmarker.c for a more complete list.)
	//--------------------------------------------------------------------------
typedef enum {
	M_UNKNOWN = 0,
	M_SOF0 = 0xC0,          // Start Of Frame N
	M_SOF1 = 0xC1,          // N indicates which compression process
	M_SOF2 = 0xC2,          // Only SOF0-SOF2 are now in common use
	M_SOF3 = 0xC3,
	M_SOF5 = 0xC5,          // NB: codes C4 and CC are NOT SOF markers
	M_SOF6 = 0xC6,
	M_SOF7 = 0xC7,
	M_SOF9 = 0xC9,
	M_SOF10 = 0xCA,
	M_SOF11 = 0xCB,
	M_SOF13 = 0xCD,
	M_SOF14 = 0xCE,
	M_SOF15 = 0xCF,
	M_SOI = 0xD8 ,         // Start Of Image (beginning of datastream)
	M_EOI = 0xD9,          // End Of Image (end of datastream)
	M_SOS = 0xDA,          // Start Of Scan (begins compressed data)
	M_JFIF = 0xE0,          // Jfif marker
	M_EXIF = 0xE1,          // Exif marker.  Also used for XMP data!
	M_XMP = 0x10E1,        // Not a real tag (same value in file as Exif!)
	M_COM = 0xFE,          // COMment 
	M_DQT = 0xDB,
	M_DHT = 0xC4,
	M_DRI = 0xDD,
	M_IPTC = 0xED,          // IPTC marker
} JPEGMarker_t;

	// Exif format descriptor stuff
extern const int BytesPerFormat[];
#define NUM_FORMATS 12

typedef enum {
	FMT_UNKNOWN = 0,
	FMT_BYTE,
	FMT_STRING,
	FMT_USHORT,
	FMT_ULONG,
	FMT_URATIONAL,
	FMT_SBYTE,
	FMT_UNDEFINED,
	FMT_SSHORT,
	FMT_SLONG,
	FMT_SRATIONAL,
	FMT_SINGLE,
	FMT_DOUBLE
} JPEGNumberFormat_t;

typedef enum
{
	MeteringMode_None = 0,
	MeteringMode_Average,
	MeteringMode_CenterWeight,
	MeteringMode_Spot,
	MeteringMode_MultiSpot,
	MeteringMode_Pattern,
	MeteringMode_Partial,
	MeteringMode_Other = 255
} MeteringMode_t;

typedef enum
{
	ExposureProgram_None = 0,
	ExposureProgram_Manual,
	ExposureProgram_Auto,
	ExposureProgram_AperturePriority,
	ExposureProgram_ShutterPriority,
	ExposureProgram_Creative,
	ExposureProgram_Operation,
	ExposureProgram_Portrait,
	ExposureProgram_Landscape
} ExposureProgram_t;

typedef enum
{
	ExposureMode_Automatic = 0,
	ExposureMode_Manual,
	ExposureMode_AutoBracketing
} ExposureMode_t;

typedef enum
{
	DistanceRange_None = 0,
	DistanceRange_Macro,
	DistanceRange_Close,
	DistanceRange_Distant
} DistanceRange_t;

typedef enum
{
	Lightsource_Undefined = 0,
	Lightsource_Daylight,
	Lightsource_Fluorescent,
	Lightsource_Incandescent,
	Lightsource_Flash,
	Lightsource_FineWeather = 9,
	Lightsource_Shade = 11
} Lightsource_t;

typedef enum
{
	WhiteBalance_Auto = 0,
	WhiteBalance_Manual
} WhiteBalance_t;

//--------------------------------------------------------------------------
typedef struct {
	UInt32 numerator;
	UInt32 denominator;
} URational;
	
typedef struct {
	SInt32 numerator;
	SInt32 denominator;
} SRational;

#pragma mark -

typedef struct {
	URational degrees;
	URational minutes;
	URational seconds;
} CoordinateTriple;

#pragma mark -
#define TAG_GPS_LAT_REF    1
#define TAG_GPS_LAT        2
#define TAG_GPS_LONG_REF   3
#define TAG_GPS_LONG       4
#define TAG_GPS_ALT_REF    5
#define TAG_GPS_ALT        6

#define MAX_DATE_COPIES 10
#define SIZE_CAMERA_MAKE 32
#define SIZE_CAMERA_MODEL 40
#define SIZE_DATETIME 20

#define SIZE_GPSLAT 32
#define SIZE_GPSLONG 32

	// IPTC entry types known to Jhead (there's many more defined)
#define IPTC_RECORD_VERSION         0x00
#define IPTC_SUPLEMENTAL_CATEGORIES 0x14
#define IPTC_KEYWORDS               0x19
#define IPTC_CAPTION                0x78
#define IPTC_AUTHOR                 0x7A
#define IPTC_HEADLINE               0x69
#define IPTC_SPECIAL_INSTRUCTIONS   0x28
#define IPTC_CATEGORY               0x0F
#define IPTC_BYLINE                 0x50
#define IPTC_BYLINE_TITLE           0x55
#define IPTC_CREDIT                 0x6E
#define IPTC_SOURCE                 0x73
#define IPTC_COPYRIGHT_NOTICE       0x74
#define IPTC_OBJECT_NAME            0x05
#define IPTC_CITY                   0x5A
#define IPTC_STATE                  0x5F
#define IPTC_COUNTRY                0x65
#define IPTC_TRANSMISSION_REFERENCE 0x67
#define IPTC_DATE                   0x37
#define IPTC_COPYRIGHT              0x0A
#define IPTC_COUNTRY_CODE           0x64
#define IPTC_REFERENCE_SERVICE      0x2D
#define IPTC_TIME_CREATED           0x3C
#define IPTC_SUB_LOCATION           0x5C
#define IPTC_IMAGE_TYPE             0x82

typedef enum {
	exifOrientation_unknown = 0,
	exifOrientation_top_left,
	exifOrientation_top_right,
	exifOrientation_bottom_right,
	exifOrientation_bottom_left,
	exifOrientation_left_top,
	exifOrientation_right_top,
	exifOrientation_right_bottom,
	exifOrientation_left_bottom	
} ExifOrientation;

typedef struct {
	NSString* name;
	ExifOrientation exifOrientation;
} UIImageOrientationDesc;

#pragma mark -
#pragma mark Misc Prototypes

unsigned char * dir_entry_address(unsigned char * start, int entry);

URational makeURational(UInt32 numerator, UInt32 denominator);
SRational makeSRational(SInt32 numerator, SInt32 denominator);

double urationalToDouble(URational ur);
URational doubleToURational(double d);

double srationalToDouble(SRational ur);
SRational doubleToSRational(double d);

CoordinateTriple locationDegreesToCoordinateTriple(CLLocationDegrees ld);
CLLocationDegrees coordinateTripleToLocationDegrees(CoordinateTriple ct);

uint8_t* put16u(uint8_t* dst, BOOL bigEndian, uint16_t putValue);

uint8_t* put32u(uint8_t* dst, BOOL bigEndian, uint32_t ui);

uint16_t get16u(uint8_t* bytes, BOOL bigEndian);

int32_t get32s(uint8_t* bytes, BOOL bigEndian);

uint32_t get32u(uint8_t* bytes, BOOL bigEndian);

URational getURational(uint8_t* bytes, BOOL bigEndian);

SRational getSRational(uint8_t* bytes, BOOL bigEndian);

CoordinateTriple getCoordinateTriple(uint8_t* bytes, BOOL bigEndian);

char* TagName(int tag);

NSString* NumberValue(uint8_t* ValuePtr, JPEGNumberFormat_t format, NSUInteger ByteCount, BOOL bigEndian);

double ConvertAny(uint8_t* ValuePtr, JPEGNumberFormat_t format, BOOL bigEndian);

