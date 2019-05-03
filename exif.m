	//--------------------------------------------------------------------------
	// Program to pull the information out of various types of EXIF digital 
	// camera files and show it in a reasonably consistent way
	//
	// This module parses the very complicated exif structures.
	//
	// Matthias Wandel
	//--------------------------------------------------------------------------

#import "jhead.h"

	//--------------------------------------------------------------------------
	// Convert exif time to Unix time structure
	//--------------------------------------------------------------------------
static int Exif2tm(struct tm * timeptr, char * ExifTime)
{
    timeptr->tm_wday = -1;
	
		// Check for format: YYYY:MM:DD HH:MM:SS format.
		// Date and time normally separated by a space, but also seen a ':' there, so
		// skip the middle space with '%*c' so it can be any character.
    timeptr->tm_sec = 0;
    int a = sscanf(ExifTime, "%d%*c%d%*c%d%*c%d:%d:%d",
				   &timeptr->tm_year, &timeptr->tm_mon, &timeptr->tm_mday,
				   &timeptr->tm_hour, &timeptr->tm_min, &timeptr->tm_sec);
	
    if (a >= 5)
	{
        if (timeptr->tm_year <= 12 && timeptr->tm_mday > 2000 && ExifTime[2] == '.')
		{
				// LG Electronics VX-9700 seems to encode the date as 'MM.DD.YYYY HH:MM'
				// can't these people read the standard?  At least they left enough room
				// in the header to put an Exif format date in there.
            int tmp;
            tmp = timeptr->tm_year;
            timeptr->tm_year = timeptr->tm_mday;
            timeptr->tm_mday = timeptr->tm_mon;
            timeptr->tm_mon = tmp;
        }
		
			// Accept five or six parameters.  Some cameras do not store seconds.
        timeptr->tm_isdst = -1;  
        timeptr->tm_mon -= 1;      // Adjust for unix zero-based months 
        timeptr->tm_year -= 1900;  // Adjust for year starting at 1900 
        return TRUE; // worked. 
    }
	
    return FALSE; // Wasn't in Exif date format.
}

static size_t EntrySize(int entryCount)
{
	/*
	 * 2 size of NumEntries ushort
	 * 12 size of each entry, times number of entries
	 * 4 size of long null end-of-entries semaphore
	 */
	return 2 + entryCount * 12 + 4;
}


