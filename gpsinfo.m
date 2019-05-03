//--------------------------------------------------------------------------
// Parsing of GPS info from exif header.
//
// Matthias Wandel,  Dec 1999 - Dec 2002 
//--------------------------------------------------------------------------
#if 0
#import "ExifReader.h"
#import "JPEGManager.h"
#include "jhead.h"

#define MAX_GPS_TAG 0x1e

static const char * GpsTags[MAX_GPS_TAG+1]= {
    "VersionID       ",//0x00  
    "LatitudeRef     ",//0x01  
    "Latitude        ",//0x02  
    "LongitudeRef    ",//0x03  
    "Longitude       ",//0x04  
    "AltitudeRef     ",//0x05  
    "Altitude        ",//0x06  
    "TimeStamp       ",//0x07  
    "Satellites      ",//0x08  
    "Status          ",//0x09  
    "MeasureMode     ",//0x0A  
    "DOP             ",//0x0B  
    "SpeedRef        ",//0x0C  
    "Speed           ",//0x0D  
    "TrackRef        ",//0x0E  
    "Track           ",//0x0F  
    "ImgDirectionRef ",//0x10  
    "ImgDirection    ",//0x11  
    "MapDatum        ",//0x12  
    "DestLatitudeRef ",//0x13  
    "DestLatitude    ",//0x14  
    "DestLongitudeRef",//0x15  
    "DestLongitude   ",//0x16  
    "DestBearingRef  ",//0x17  
    "DestBearing     ",//0x18  
    "DestDistanceRef ",//0x19  
    "DestDistance    ",//0x1A  
    "ProcessingMethod",//0x1B  
    "AreaInformation ",//0x1C  
    "DateStamp       ",//0x1D  
    "Differential    ",//0x1E
};

#endif
