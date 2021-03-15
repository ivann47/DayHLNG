enum ENUM_HIGH_ORDER_TYPE {
	DAYHL_BUY_STOP = ORDER_TYPE_BUY_STOP,
	DAYHL_SELL_LIMIT = ORDER_TYPE_SELL_LIMIT
};

enum ENUM_LOW_ORDER_TYPE {
	DAYHL_SELL_STOP = ORDER_TYPE_SELL_STOP,
	DAYHL_BUY_LIMIT = ORDER_TYPE_BUY_LIMIT
};

struct ExpertParams {
	ENUM_HIGH_ORDER_TYPE highOrderType;
	ENUM_LOW_ORDER_TYPE lowOrderType;
	uint highOffset;
	uint lowOffset;
	uint minLimit;
	uint maxLimit;
	double riskLimit;
	double fixedVolume;
	uint fixedTP;
	uint fixedSL;
	double profitToRiskRatio;
	uint breakevenTriggerLevel;
	uint breakevenValue;
	uint fixedTrailLevel;
	uint fixedTrail;
	uint maxOpenedPositions;
};
