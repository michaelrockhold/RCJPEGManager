//
//  JPEGHeader.h
//  StaticMapHere
//
//  Created by Michael Rockhold on 1/4/10.
//  Copyright 2010 The Rockhold Company. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import "jhead.h"

@class Section;

@interface JPEGManager : NSObject
{	
	NSMutableArray*		_sections;
	NSData*				_imageData;
	NSData*				_thumbnail;
	
	double				_focalplaneXRes;
	double				_focalplaneUnits;
	int					_exifImageWidth;
	int					_exifImageLength;

	UIImageOrientation	_orientation;
	NSString*			_comments;
	NSString*			_cameraMake;
	NSString*			_cameraModel;
	NSString*			_imageDescription;
	NSString*			_software;
	NSString*			_artist;
	NSString*			_copyright;
	NSString*			_dateTime;
	size_t				_numDateTimeTags;
		// Info in the jfif header.
		// This info is not used much - jhead used to just replace it with default
		// values, and over 10 years, only two people pointed this out.
	BOOL	_JfifHeaderPresent;
	char	_JfifHeaderResolutionUnits;
	short	_JfifHeaderXDensity;
	short	_JfifHeaderYDensity;
	
    int						_height;
	int						_width;
    BOOL					_isColor;
    int						_process;
    uint8_t					_flashUsed;
    float					_focalLength;
    float					_exposureTime;
    float					_apertureFNumber;
    float					_distance;
    float					_CCDWidth;
    float					_exposureBias;
    float					_digitalZoomRatio;
    int						_focalLength35mmEquiv; // Exif 2.2 tag - usually not present.
    WhiteBalance_t			_whitebalance;
    MeteringMode_t			_meteringMode;
    ExposureProgram_t		_exposureProgram;
    ExposureMode_t			_exposureMode;
    int						_ISOequivalent;
    Lightsource_t			_lightSource;
    DistanceRange_t			_distanceRange;
	
    float					_xResolution;
    float					_yResolution;
    int						_resolutionUnit;

	BOOL					_gpsInfoPresent;
	CLLocationCoordinate2D	_coordinate;
	CLLocationDistance		_altitude;
}

@property (nonatomic, retain, readonly)	NSMutableArray*		sections;
@property (nonatomic, retain)			NSData*				imageData;
@property (nonatomic)					UIImageOrientation	orientation;

@property (nonatomic, retain)			NSString*	comments;
@property (nonatomic, retain)			NSString*	cameraMake;
@property (nonatomic, retain)			NSString*	cameraModel;
@property (nonatomic, retain)			NSString*	imageDescription;
@property (nonatomic, retain)			NSString*	software;
@property (nonatomic, retain)			NSString*	artist;
@property (nonatomic, retain)			NSString*	copyright;
@property (nonatomic, retain)			NSString*	dateTime;
@property (nonatomic)					size_t		numDateTimeTags;

@property (nonatomic)					int					height;
@property (nonatomic)					int					width;
@property (nonatomic)					BOOL				isColor;
@property (nonatomic)					int					process;
@property (nonatomic)					uint8_t				flashUsed;
@property (nonatomic)					float				focalLength;
@property (nonatomic)					float				exposureTime;
@property (nonatomic)					float				apertureFNumber;
@property (nonatomic)					float				distance;
@property (nonatomic)					float				CCDWidth;
@property (nonatomic)					float				exposureBias;
@property (nonatomic)					float				digitalZoomRatio;
@property (nonatomic)					int					focalLength35mmEquiv; // Exif 2.2 tag - usually not present.
@property (nonatomic)					WhiteBalance_t		whitebalance;
@property (nonatomic)					MeteringMode_t		meteringMode;
@property (nonatomic)					ExposureProgram_t	exposureProgram;
@property (nonatomic)					ExposureMode_t		exposureMode;
@property (nonatomic)					int					ISOequivalent;
@property (nonatomic)					Lightsource_t		lightSource;
@property (nonatomic)					DistanceRange_t		distanceRange;

@property (nonatomic)					float				xResolution;
@property (nonatomic)					float				yResolution;
@property (nonatomic)					int					resolutionUnit;

@property (nonatomic)					BOOL				gpsInfoPresent;
@property (nonatomic)					CLLocationCoordinate2D coordinate;
@property (nonatomic)					CLLocationDistance	altitude;

@property (nonatomic)					BOOL	JfifHeaderPresent;
@property (nonatomic)					char	JfifHeaderResolutionUnits;
@property (nonatomic)					short	JfifHeaderXDensity;
@property (nonatomic)					short	JfifHeaderYDensity;

@property (nonatomic)					double	focalplaneXRes;
@property (nonatomic)					double	focalplaneUnits;
@property (nonatomic)					int		exifImageWidth;
@property (nonatomic)					int		exifImageLength;

@property (nonatomic, retain)			NSData* thumbnail;

+(NSData*)dataWithImage:(UIImage*)image
			   location:(CLLocation*)location 
				  title:(NSString*)title 
				comment:(NSString*)comment
				 artist:(NSString*)artist
			   software:(NSString*)software
			  copyright:(NSString*)copyright;

-(NSData*)createJPEGData;

-(BOOL)has_EXIF;
-(void)recreateEXIFSection;

-(void)process_EXIF:(NSData*)exifData;

+(const char*)processTableDesc:(int)processType;

-(void)readJpegSections:(NSData*)jpegData;

-(void)addSection:(Section*)section;
-(void)addExifSection:(Section*)section;
-(void)addCommentSection:(Section*)section;

-(Section*)findSection:(JPEGMarker_t)sectionType;
-(BOOL)removeSectionType:(JPEGMarker_t)sectionType;
-(BOOL)removeUnknownSections;

-(void)process_COM:(NSData*)sectionData;
-(void)process_SOFn:(NSData*)sectionData marker:(JPEGMarker_t)marker;
@end

