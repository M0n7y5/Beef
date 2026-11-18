#include "DbgCallConvSysV.h"
#include "DbgTargetHost.h"

USING_NS_BF_DBG;

enum DbgSlotCode
{
	DbgSlotCode_None,
	DbgSlotCode_Float,
	DbgSlotCode_Double,
	DbgSlotCode_Int32,
	DbgSlotCode_Int
};

static void SysVFillSlots(DbgType* type, int offset, DbgSlotCode* slots, int slotCount)
{
	type = type->RemoveModifiers();
	if (type->IsTypedPrimitive())
		type = type->mTypeParam->RemoveModifiers();
	if (type->mTypeCode == DbgType_Enum)
		type = (type->mTypeParam != NULL) ? type->mTypeParam->RemoveModifiers() : type;

	int slotIdx = offset / 4;
	if ((slotIdx < 0) || (slotIdx >= slotCount))
		return;

	if ((type->mTypeCode == DbgType_Struct) && (!type->IsBfObject()))
	{
		type->PopulateType();
		for (auto baseEntry : type->mBaseTypes)
		{
			if (baseEntry->mBaseType != NULL)
				SysVFillSlots(baseEntry->mBaseType, offset + baseEntry->mThisOffset, slots, slotCount);
		}
		for (auto member : type->mMemberList)
		{
			if ((member->mIsStatic) || (member->mIsConst) || (member->mType == NULL))
				continue;
			SysVFillSlots(member->mType, offset + member->mMemberOffset, slots, slotCount);
		}
		return;
	}
	if (type->IsSizedArray())
	{
		DbgType* elementType = type->mTypeParam;
		int stride = (int)elementType->GetStride();
		if (stride <= 0)
			return;
		int count = (int)(type->GetByteCount() / stride);
		for (int elementIdx = 0; elementIdx < count; elementIdx++)
			SysVFillSlots(elementType, offset + elementIdx * stride, slots, slotCount);
		return;
	}
	if (type->mTypeCode == DbgType_Single)
		slots[slotIdx] = DbgSlotCode_Float;
	else if (type->mTypeCode == DbgType_Double)
		slots[slotIdx] = DbgSlotCode_Double;
	else if (type->mTypeCode == DbgType_i32)
		slots[slotIdx] = DbgSlotCode_Int32;
	else
		slots[slotIdx] = DbgSlotCode_Int;
}

// Must match BfModule's splattable rule
bool DbgCallConvSysV::IsSplattable(DbgType* type)
{
	type = type->RemoveModifiers();
	if (type->IsTypedPrimitive())
		return true;
	if ((type->mTypeCode != DbgType_Struct) || (type->IsBfObject()))
		return false;

	int dataCount = 0;
	bool hadNonSplattable = false;
	std::function<void(DbgType*, int)> _Count = [&](DbgType* checkType, int depth)
	{
		checkType = checkType->RemoveModifiers();
		if ((hadNonSplattable) || (depth > 64))
		{
			hadNonSplattable = true;
			return;
		}
		if (checkType->IsTypedPrimitive())
		{
			dataCount++;
			return;
		}
		if (checkType->mTypeCode == DbgType_Union)
		{
			hadNonSplattable = true;
			return;
		}
		if ((checkType->mTypeCode == DbgType_Struct) && (!checkType->IsBfObject()))
		{
			checkType->PopulateType();
			for (auto baseEntry : checkType->mBaseTypes)
			{
				if (baseEntry->mBaseType != NULL)
					_Count(baseEntry->mBaseType, depth + 1);
			}
			for (auto member : checkType->mMemberList)
			{
				if ((member->mIsStatic) || (member->mIsConst) || (member->mType == NULL))
					continue;
				_Count(member->mType, depth + 1);
			}
			return;
		}
		if (checkType->IsSizedArray())
		{
			hadNonSplattable = true;
			return;
		}
		if (checkType->GetByteCount() > 0)
			dataCount++;
	};
	_Count(type, 0);
	return (dataCount <= 3) && (!hadNonSplattable);
}

// Must match BfTypeInstance::GetLoweredType for x64 outside Windows
bool DbgCallConvSysV::GetLoweredParts(DbgType* type, Array<DbgSysVPart>& outParts)
{
	outParts.Clear();
	type = type->RemoveModifiers();
	if ((type->mTypeCode != DbgType_Struct) || (type->IsBfObject()) || (IsSplattable(type)))
		return false;

	int instSize = (int)type->GetByteCount();
	auto _Add = [&](DbgSysVRegKind kind, int offset, int size)
	{
		DbgSysVPart part;
		part.mKind = kind;
		part.mOffset = offset;
		part.mSize = size;
		outParts.Add(part);
	};

	if ((instSize >= 4) && (instSize <= 16))
	{
		DbgSlotCode slots[8] = { DbgSlotCode_None };
		SysVFillSlots(type, 0, slots, 8);

		bool handled = false;
		bool vector = false;
		if (((slots[0] == DbgSlotCode_Float) && (slots[1] == DbgSlotCode_Float) && (slots[2] == DbgSlotCode_Float) && (slots[3] == DbgSlotCode_Float)) ||
			((slots[0] == DbgSlotCode_Int32) && (slots[1] == DbgSlotCode_Int32) && (slots[2] == DbgSlotCode_Int32) && (slots[3] == DbgSlotCode_Int32)))
		{
			handled = true;
			vector = true;
		}

		if (vector)
		{
			_Add(DbgSysVRegKind_Sse, 0, 16);
			return true;
		}

		DbgSysVRegKind kind1 = DbgSysVRegKind_Int;
		int size1 = 0;
		DbgSysVRegKind kind2 = DbgSysVRegKind_Int;
		int size2 = 0;
		if (instSize >= 8)
			size1 = 8;
		if (instSize == 8)
			handled = true;
		if ((instSize == 9) || (instSize == 10) || (instSize == 12) || (instSize == 16))
		{
			handled = true;
			size2 = instSize - 8;
		}
		if ((slots[0] == DbgSlotCode_Float) && (slots[1] == DbgSlotCode_None))
		{
			handled = true;
			kind1 = DbgSysVRegKind_Sse;
			size1 = 4;
		}
		if ((slots[0] == DbgSlotCode_Float) && (slots[1] == DbgSlotCode_Float))
		{
			kind1 = DbgSysVRegKind_Sse;
			size1 = 8;
		}
		if (slots[0] == DbgSlotCode_Double)
		{
			kind1 = DbgSysVRegKind_Sse;
			size1 = 8;
		}
		if ((slots[2] == DbgSlotCode_Float) && (instSize == 12))
		{
			kind2 = DbgSysVRegKind_Sse;
			size2 = 4;
		}
		if ((slots[2] == DbgSlotCode_Float) && (slots[3] == DbgSlotCode_Float))
		{
			kind2 = DbgSysVRegKind_Sse;
			size2 = 8;
		}
		if (slots[2] == DbgSlotCode_Double)
		{
			kind2 = DbgSysVRegKind_Sse;
			size2 = 8;
		}

		if (handled)
		{
			_Add(kind1, 0, size1);
			if (size2 > 0)
				_Add(kind2, 8, size2);
			return true;
		}
	}

	if ((instSize >= 1) && (instSize <= 8))
	{
		_Add(DbgSysVRegKind_Int, 0, instSize);
		return true;
	}
	return false;
}

bool DbgCallConvSysV::GetLoweredReturnParts(DbgType* returnType, Array<DbgSysVPart>& outParts)
{
	outParts.Clear();
	if (returnType == NULL)
		return false;
	returnType = returnType->RemoveModifiers();
	if ((!returnType->IsCompositeType()) || (returnType->IsTypedPrimitive()) || (returnType->GetByteCount() == 0))
		return false;
	return GetLoweredParts(returnType, outParts);
}

static bool SysVReadValueBytes(DbgTargetHost* host, const DbgTypedValue& typedValue, int byteCount, uint8* outBytes)
{
	memset(outBytes, 0, 16);
	if (typedValue.mSrcAddress != 0)
		return host->ReadMemory(typedValue.mSrcAddress, byteCount, outBytes);
	memcpy(outBytes, &typedValue.mInt64, BF_MIN(byteCount, 8));
	return true;
}

bool DbgCallConvSysV::SetupCall(DbgTargetHost* host, DbgSubprogram* method, SizedArrayImpl<DbgMethodArgument>& argPushQueue, const DbgTypedValue& structRetVal,
	CPURegisters* registers, DbgTypedValue& outThisVal, String& outError)
{
	static const int kNumIntArgRegs = 6;
	static const int kNumSseArgRegs = 8;
	int64* intArgRegs[kNumIntArgRegs] = { &registers->mIntRegs.rdi, &registers->mIntRegs.rsi, &registers->mIntRegs.rdx,
		&registers->mIntRegs.rcx, &registers->mIntRegs.r8, &registers->mIntRegs.r9 };
	int intRegCount = 0;
	int sseRegCount = 0;
	Array<uint64> stackSlots;

	auto _AddInt = [&](uint64 val)
	{
		if (intRegCount < kNumIntArgRegs)
			*intArgRegs[intRegCount++] = (int64)val;
		else
			stackSlots.Add(val);
	};
	auto _AddSse = [&](const uint8* bytes, int size)
	{
		if (sseRegCount < kNumSseArgRegs)
		{
			uint8* xmm = (uint8*)&registers->mXmmRegsArray[sseRegCount++];
			memset(xmm, 0, 16);
			memcpy(xmm, bytes, size);
			return true;
		}
		if (size > 8)
			return false;
		uint64 val = 0;
		memcpy(&val, bytes, size);
		stackSlots.Add(val);
		return true;
	};
	auto _AddLowered = [&](const DbgTypedValue& typedValue, const Array<DbgSysVPart>& parts)
	{
		uint8 bytes[16];
		if (!SysVReadValueBytes(host, typedValue, (int)typedValue.mType->GetByteCount(), bytes))
		{
			outError = "Unable to read an argument from the target";
			return false;
		}
		for (auto& part : parts)
		{
			if (part.mKind == DbgSysVRegKind_Sse)
			{
				if (!_AddSse(bytes + part.mOffset, part.mSize))
				{
					outError = "Too many vector arguments for the Linux debugger to pass";
					return false;
				}
			}
			else
			{
				uint64 val = 0;
				memcpy(&val, bytes + part.mOffset, part.mSize);
				_AddInt(val);
			}
		}
		return true;
	};
	auto _AddScalar = [&](const DbgTypedValue& typedValue)
	{
		DbgType* type = typedValue.mType->RemoveModifiers();
		if (type->IsTypedPrimitive())
			type = type->mTypeParam->RemoveModifiers();
		if (type->mTypeCode == DbgType_Single)
			_AddSse((const uint8*)&typedValue.mSingle, 4);
		else if (type->mTypeCode == DbgType_Double)
			_AddSse((const uint8*)&typedValue.mDouble, 8);
		else
		{
			uint64 val = (uint64)typedValue.mInt64;
			int byteCount = (int)type->GetByteCount();
			if ((byteCount > 0) && (byteCount < 8))
				val &= ((uint64)1 << (byteCount * 8)) - 1;
			_AddInt(val);
		}
	};

	Array<DbgSysVPart> returnParts;
	bool returnLowered = GetLoweredReturnParts(method->mReturnType, returnParts);
	if ((structRetVal.mSrcAddress != 0) && (!returnLowered))
		_AddInt((uint64)structRetVal.mSrcAddress);

	for (int argIdx = 0; argIdx < (int)argPushQueue.size(); argIdx++)
	{
		auto& typedValue = argPushQueue[argIdx].mTypedValue;
		DbgType* type = typedValue.mType->RemoveModifiers();

		if ((argIdx == 0) && (method->mHasThis) && (!method->ThisIsSplat()))
		{
			outThisVal = typedValue;
			DbgType* thisParamType = (method->mParams.mHead != NULL) ? method->mParams.mHead->mType : NULL;
			bool thisByValue = (thisParamType != NULL) && (thisParamType->RemoveModifiers()->IsValueType()) && (type->IsCompositeType());
			if ((thisByValue) && (type->IsTypedPrimitive()))
			{
				_AddScalar(typedValue);
				continue;
			}
			Array<DbgSysVPart> parts;
			if ((thisByValue) && (GetLoweredParts(type, parts)))
			{
				if (!_AddLowered(typedValue, parts))
					return true;
				continue;
			}
			_AddInt(type->IsCompositeType() ? (uint64)typedValue.mSrcAddress : (uint64)typedValue.mPtr);
			continue;
		}

		if (type->GetByteCount() == 0)
			continue;

		if ((type->IsCompositeType()) && (!type->IsTypedPrimitive()) && (!type->IsBfObject()))
		{
			if (type->GetByteCount() > 16)
			{
				outError = StrFormat("Calls passing '%s' by value are not supported on Linux: the debug info does not say whether it is passed by pointer or copied on the stack (CRepr)",
					type->ToString().c_str());
				return true;
			}
			Array<DbgSysVPart> parts;
			if (GetLoweredParts(type, parts))
			{
				if (!_AddLowered(typedValue, parts))
					return true;
			}
			else
				_AddInt((uint64)typedValue.mSrcAddress);
			continue;
		}

		if (type->IsCompositeType())
		{
			if (type->IsTypedPrimitive())
				_AddScalar(typedValue);
			else
				_AddInt((uint64)typedValue.mSrcAddress);
			continue;
		}
		_AddScalar(typedValue);
	}

	// The call must see a 16-byte aligned stack once the return address is pushed after the arguments
	addr_target* regSP = registers->GetSPRegisterRef();
	*regSP &= ~(addr_target)0xF;
	if ((stackSlots.size() & 1) != 0)
		*regSP -= 8;
	for (int slotIdx = (int)stackSlots.size() - 1; slotIdx >= 0; slotIdx--)
		host->PushValue(registers, (int64)stackSlots[slotIdx]);

	// A variadic callee reads the number of vector registers used from al
	registers->mIntRegs.rax = sseRegCount;
	return true;
}

void DbgCallConvSysV::StoreLoweredReturn(DbgTargetHost* host, const Array<DbgSysVPart>& parts, CPURegisters* registers, addr_target destAddr)
{
	int64 intRets[2] = { registers->mIntRegs.rax, registers->mIntRegs.rdx };
	int intIdx = 0;
	int sseIdx = 0;
	for (auto& part : parts)
	{
		if (part.mKind == DbgSysVRegKind_Sse)
			host->WriteMemory(destAddr + part.mOffset, &registers->mXmmRegsArray[sseIdx++], part.mSize);
		else
			host->WriteMemory(destAddr + part.mOffset, &intRets[intIdx++], part.mSize);
	}
}
