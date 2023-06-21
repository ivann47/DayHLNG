//
// DayHLNG.mq5
// Alexey Ivannikov (alexey.a.ivannikov@gmail.com)
//
#define     MName          "DayHLNG"
#define     MVersion       "2.6"
#define     MBuild         "2023-06-21 23:20 MSK"
#define     MCopyright     "Copyright \x00A9 2021, Alexey Ivannikov (alexey.a.ivannikov@gmail.com), All rights reserved"
//---------------------------------------------------------------------------------------------------------------------
#property   version        MVersion
#property   description    MName
#property   description    "Extended version of the DayHL expert advisor (Build "MBuild" alpha5)"
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
