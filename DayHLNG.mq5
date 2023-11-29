//
// DayHLNG.mq5
// Alexey Ivannikov (alexey.a.ivannikov@gmail.com)
//
#define     MName          "DayHLNG"
#define		MMajor		   "2"
#define		MMinor		   "10"
#define		MPatchlevel	   "0"
//#define     MVersion       "2.10"
#define     MCopyright     "Copyright \x00A9 2021, Alexey Ivannikov (alexey.a.ivannikov@gmail.com), All rights reserved"
//---------------------------------------------------------------------------------------------------------------------
#property   version        MMajor"."MMinor
#property   description    MName
#property   description    "Extended version of the DayHL expert advisor (version "MMajor"."MMinor"."MPatchlevel")"
#property   copyright      MCopyright

#include "DayHLNG.mqh"

CDayHLNG expert;

int OnInit() {
	return expert.OnInit();
}

void OnDeinit(const int reason) {
	expert.OnDeinit(reason);
}

void OnTick() {
	expert.OnTick();
}

void OnTimer() {
	expert.OnTimer();
}
