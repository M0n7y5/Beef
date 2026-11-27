#pragma once

#include "DbgModule.h"
#include "DbgExprEvaluator.h"

NS_BF_DBG_BEGIN

class DbgTargetHost;

enum DbgSysVRegKind
{
	DbgSysVRegKind_Int,
	DbgSysVRegKind_Sse
};

struct DbgSysVPart
{
	DbgSysVRegKind mKind;
	int mOffset;
	int mSize;
};

class DbgCallConvSysV
{
public:
	static bool IsSplattable(DbgType* type);
	static bool GetLoweredParts(DbgType* type, Array<DbgSysVPart>& outParts);
	static bool GetLoweredReturnParts(DbgType* returnType, Array<DbgSysVPart>& outParts);
	static bool SetupCall(DbgTargetHost* host, DbgSubprogram* method, SizedArrayImpl<DbgMethodArgument>& argPushQueue, const DbgTypedValue& structRetVal,
		CPURegisters* registers, DbgTypedValue& outThisVal, String& outError);
	static void StoreLoweredReturn(DbgTargetHost* host, const Array<DbgSysVPart>& parts, CPURegisters* registers, addr_target destAddr);
};

NS_BF_DBG_END
