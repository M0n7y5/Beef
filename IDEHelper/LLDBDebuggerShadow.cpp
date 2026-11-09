#include "LLDBDebugger.h"

#ifdef LLDB_ENABLED

#include "DebugManager.h"
#include "DebugTarget.h"
#include "DbgModule.h"
#include "ElfDbgModule.h"
#include "DWARFInfo.h"
#include "llvm/Demangle/Demangle.h"
#include "BeefySysLib/util/AllocDebug.h"

USING_NS_BF;
USING_NS_BF_DBG;

void LLDBLog(const char* fmt ...);

static const int SHADOW_MAX_REPORTED_MISMATCHES = 200;

static String ShadowNormalizePath(const StringImpl& path)
{
	String result = path;
	result.Replace('\\', '/');
	while (result.Contains("/./"))
		result.Replace("/./", "/");
	while (result.Contains("//"))
		result.Replace("//", "/");
	return result;
}

// LLDB names functions from their linkage names: no Beef parameter lists, '.' for nested types, "~ClassA" for
// destructors and the "__im" suffix of methods taking a splatted mutable this
static String ShadowFunctionName(const StringImpl& name)
{
	String result = name;
	int parenIdx = (int)result.IndexOf('(');
	if (parenIdx != -1)
		result.RemoveToEnd(parenIdx);
	result.Replace('+', '.');
	if (result.EndsWith("__im"))
		result.RemoveToEnd(result.length() - 4);
	int lastDot = (int)result.LastIndexOf('.');
	if ((lastDot != -1) && (lastDot + 1 < (int)result.length()) && (result[lastDot + 1] == '~'))
	{
		result.RemoveToEnd(lastDot + 1);
		result += "~this";
	}
	return result;
}

// LLDB shows an inlined frame by its DW_AT_name alone, so only the unqualified name and the linkage name are compared
static String ShadowInlineName(const StringImpl& name)
{
	String result = ShadowFunctionName(name);
	int nameStart = (int)result.IndexOf('!') + 1;
	int nameEnd = (int)result.IndexOf('!', nameStart);
	if (nameEnd == -1)
		nameEnd = (int)result.length();
	int lastDot = (int)result.LastIndexOf('.', nameEnd - 1);
	if (lastDot >= nameStart)
		result.Remove(nameStart, lastDot + 1 - nameStart);
	return result;
}

// LLDB hides artificial parameters (a lambda's __closure) as runtime support values, and DebugTarget gives a
// repeated name an '@' per earlier use, cuts a "$a" alias suffix and lists a splatted parameter once by its own name
static String ShadowLLDBAutos(lldb::SBFrame& frame)
{
	lldb::SBVariablesOptions options;
	options.SetIncludeArguments(true);
	options.SetIncludeLocals(true);
	options.SetIncludeStatics(false);
	options.SetInScopeOnly(true);
	options.SetIncludeRuntimeSupportValues(true);
	auto variables = frame.GetVariables(options);

	Array<String> names;
	for (int i = 0; i < (int)variables.GetSize(); i++)
	{
		const char* namePtr = variables.GetValueAtIndex(i).GetName();
		if (namePtr == NULL)
			continue;
		if (namePtr[0] == '$')
		{
			const char* splatEnd = strchr(namePtr + 1, '$');
			if (splatEnd == NULL)
				continue;
			String splatName(namePtr + 1, (int)(splatEnd - namePtr - 1));
			if (!names.Contains(splatName))
				names.Add(splatName);
			continue;
		}
		String name = namePtr;
		while (names.Contains(name))
			name.Insert(0, '@');
		names.Add(name);
	}

	String result = "\n";
	String lastAlias;
	for (auto& name : names)
	{
		int aliasIdx = (int)name.IndexOf("$a");
		if (aliasIdx == -1)
		{
			result += name + "\n";
			continue;
		}
		name.RemoveToEnd(aliasIdx);
		if (name != lastAlias)
			result += name + "\n";
		lastAlias = name;
	}
	return result;
}

void LLDBDebugger::ShadowInit()
{
	const char* shadowEnv = getenv("BEEF_DBG_SHADOW");
	mShadowEnabled = (shadowEnv != NULL) && (atoi(shadowEnv) != 0);
	mShadowExtraCount = 0;
	const char* reportEnv = getenv("BEEF_DBG_SHADOW_REPORT");
	if (reportEnv != NULL)
		mShadowReportPath = reportEnv;
}

static const char* sShadowFlippedQueries[] = { "addr_line", "addr_symbol", "frame_name", "frame_line", "inline_depth", "inline_name", "inline_line", "frame_map", "tls_addr", "breakpoint",
	"autos_subset", "autos_subset_inline", "line_calls", "line_calls_nonempty" };

bool LLDBDebugger::ShadowIsFlipped(const char* query)
{
	for (auto flippedQuery : sShadowFlippedQueries)
	{
		if (strcmp(flippedQuery, query) == 0)
			return true;
	}
	return false;
}

// Source lines in DBGSHADOW lines are 0-based, the IDE's convention
void LLDBDebugger::ShadowCompare(const char* query, const StringImpl& lldbResult, const StringImpl& beefResult)
{
	mShadowQueryCounts[query]++;
	if (lldbResult == beefResult)
		return;
	mShadowMismatchCounts[query]++;
	ShadowReportLine(StrFormat("DBGSHADOW %s: lldb=%s beef=%s returned=%s", query, lldbResult.c_str(), beefResult.c_str(), ShadowIsFlipped(query) ? "beef" : "lldb"));
}

void LLDBDebugger::ShadowReportLine(const StringImpl& line)
{
	LLDBLog("%s\n", line.c_str());
	if (mShadowMismatchLines.size() < SHADOW_MAX_REPORTED_MISMATCHES)
		mShadowMismatchLines.Add(line);
}

String LLDBDebugger::HostAddressSourceLocation(intptr address)
{
	DbgSubprogram* subprogram = NULL;
	DbgSrcFile* srcFile = NULL;
	DbgLineData* lineData = FindLineDataAtAddress((addr_target)address, &subprogram, &srcFile);
	if ((lineData == NULL) || (srcFile == NULL))
		return String();
	return StrFormat("%s:%d", ShadowNormalizePath(srcFile->GetLocalPath()).c_str(), lineData->mLine);
}

void LLDBDebugger::ShadowCheckFrames()
{
	if ((mDebugTarget == NULL) || (mCallStack.IsEmpty()))
		return;

	int concreteIdx = -1;
	for (int beefIdx = 0; beefIdx < (int)mCallStack.size(); beefIdx++)
	{
		if (mCallStack[beefIdx]->mInInlineMethod)
			continue;
		concreteIdx++;
		if (concreteIdx >= (int)mHostFrameGroupStart.size())
			break;

		int groupStart = mHostFrameGroupStart[concreteIdx];
		int lldbIdx = groupStart;
		while ((lldbIdx < (int)mLLDBFrames.size()) && (mLLDBFrames[lldbIdx].IsInlined()))
			lldbIdx++;
		if (lldbIdx >= (int)mLLDBFrames.size())
			break;

		intptr addr = 0;
		String file;
		int32 hotIdx = 0;
		int32 defLineStart = 0;
		int32 defLineEnd = 0;
		int32 line = 0;
		int32 column = 0;
		int32 language = 0;
		int32 stackSize = 0;
		int8 flags = 0;

		String lldbName = LLDBStackFrameInfo(lldbIdx, &addr, &file, &hotIdx, &defLineStart, &defLineEnd, &line, &column, &language, &stackSize, &flags);
		LLDBStackFrameInfo(groupStart, &addr, &file, &hotIdx, &defLineStart, &defLineEnd, &line, &column, &language, &stackSize, &flags);
		String lldbLine = StrFormat("%s:%d", ShadowNormalizePath(file).c_str(), line);

		String beefName = DbgTargetHost::GetStackFrameInfo(beefIdx, &addr, &file, &hotIdx, &defLineStart, &defLineEnd, &line, &column, &language, &stackSize, &flags);
		String beefLine = StrFormat("%s:%d", ShadowNormalizePath(file).c_str(), line);

		int beefGroupEnd = beefIdx + 1;
		while ((beefGroupEnd < (int)mCallStack.size()) && (mCallStack[beefGroupEnd]->mInInlineMethod))
			beefGroupEnd++;
		int beefDepth = beefGroupEnd - beefIdx - 1;
		int lldbDepth = lldbIdx - groupStart;
		if ((beefDepth > 0) && (mCallStack[beefIdx]->mSubProgram != NULL))
			beefName = DbgTargetHost::GetStackFrameInfo(beefGroupEnd - 1, &addr, &file, &hotIdx, &defLineStart, &defLineEnd, &line, &column, &language, &stackSize, &flags);

		WdStackFrame* wdStackFrame = mCallStack[beefIdx];
		addr_target sourcePC = wdStackFrame->GetSourcePC();
		if (wdStackFrame->mSubProgram != NULL)
		{
			String lldbFrameName = ShadowFunctionName(lldbName);
			// LLDB falls back to the linkage name when its demangler rejects one (delegate Invoke), where DebugTarget names the delegate type
			DbgSubprogram* nameSubprogram = mCallStack[beefGroupEnd - 1]->mSubProgram;
			int moduleEnd = (int)lldbName.IndexOf('!');
			if ((nameSubprogram != NULL) && (nameSubprogram->mLinkName != NULL) && (strcmp(lldbName.c_str() + moduleEnd + 1, nameSubprogram->mLinkName) == 0))
				lldbFrameName = ShadowFunctionName(beefName);
			String beefFrameName = ShadowFunctionName(beefName);
			// DebugTarget marks a replaced hot version with '#' and names hot code by its linked module, LLDB by the object file
			if (beefFrameName.StartsWith('#'))
				beefFrameName.Remove(0, 1);
			int lldbModuleEnd = (int)lldbFrameName.IndexOf('!');
			int beefModuleEnd = (int)beefFrameName.IndexOf('!');
			if ((lldbFrameName.StartsWith("BeefHot_")) && (lldbModuleEnd != -1) && (beefModuleEnd != -1))
				lldbFrameName = beefFrameName.Substring(0, beefModuleEnd) + lldbFrameName.Substring(lldbModuleEnd);
			ShadowCompare("frame_name", lldbFrameName, beefFrameName);
			ShadowCompare("frame_line", lldbLine, beefLine);
			ShadowCompare("inline_depth", StrFormat("%d", lldbDepth), StrFormat("%d", beefDepth));
			if (lldbDepth == beefDepth)
			{
				for (int depthIdx = 0; depthIdx <= lldbDepth; depthIdx++)
				{
					String lldbInlineName = LLDBStackFrameInfo(groupStart + depthIdx, &addr, &file, &hotIdx, &defLineStart, &defLineEnd, &line, &column, &language, &stackSize, &flags);
					String lldbInlineLine = StrFormat("%s:%d", ShadowNormalizePath(file).c_str(), line);
					String beefInlineName = DbgTargetHost::GetStackFrameInfo(beefIdx + depthIdx, &addr, &file, &hotIdx, &defLineStart, &defLineEnd, &line, &column, &language, &stackSize, &flags);
					String beefInlineLine = StrFormat("%s:%d", ShadowNormalizePath(file).c_str(), line);
					if (depthIdx < lldbDepth)
						ShadowCompare("inline_name", ShadowInlineName(lldbInlineName), ShadowInlineName(beefInlineName));
					if (depthIdx > 0)
						ShadowCompare("inline_line", lldbInlineLine, beefInlineLine);
				}
			}
			String lldbAddrLine = LLDBAddressSourceLocation((intptr)sourcePC);
			int columnColon = (int)lldbAddrLine.LastIndexOf(':');
			if (columnColon > 0)
				lldbAddrLine.RemoveToEnd(columnColon);
			int lineColon = (int)lldbAddrLine.LastIndexOf(':');
			if (lineColon > 0)
			{
				int lldbLineNum = atoi(lldbAddrLine.c_str() + lineColon + 1);
				lldbAddrLine.RemoveToEnd(lineColon);
				lldbAddrLine += StrFormat(":%d", lldbLineNum - 1);
			}
			ShadowCompare("addr_line", ShadowNormalizePath(lldbAddrLine), HostAddressSourceLocation((intptr)sourcePC));

			int autosDepth = (lldbDepth == beefDepth) ? lldbDepth : 0;
			for (int depthIdx = 0; depthIdx <= autosDepth; depthIdx++)
			{
				String lldbAutos = ShadowLLDBAutos(mLLDBFrames[groupStart + depthIdx]);
				String beefAutos = DbgTargetHost::GetAutoLocals(beefIdx + depthIdx, false);
				String missing;
				for (auto name : beefAutos.Split('\n'))
				{
					if (name.IsEmpty())
						continue;
					String key = "\n";
					key += name;
					key += "\n";
					if (!lldbAutos.Contains(key))
					{
						missing += name;
						missing += " ";
					}
				}
				String beefKeys = "\n";
				beefKeys += beefAutos;
				for (auto name : lldbAutos.Split('\n'))
				{
					if (name.IsEmpty())
						continue;
					String key = "\n";
					key += name;
					key += "\n";
					if (!beefKeys.Contains(key))
					{
						missing += "lldb:";
						missing += name;
						missing += " ";
					}
				}
				DbgSubprogram* frameSubprogram = mCallStack[beefIdx + depthIdx]->mSubProgram;
				bool isInlineFrame = (frameSubprogram != NULL) && (frameSubprogram->mInlineeInfo != NULL);
				// An empty list passes the subset rule trivially, so inline frames with autos are counted on their own
				if ((isInlineFrame) && (!beefAutos.IsEmpty()))
					mShadowQueryCounts["autos_inline_answered"]++;
				ShadowCompare(isInlineFrame ? "autos_subset_inline" : "autos_subset", "", missing);
			}

			if ((beefIdx == 0) && (beefDepth == 0))
				ShadowCheckLineCalls((addr_target)wdStackFrame->mRegisters.GetPC());
		}

		// Modules with only .dynsym are left out: LLDB also reads MiniDebugInfo locals and symbol versions there
		DbgModule* symbolModule = mDebugTarget->FindDbgModuleForAddress(sourcePC);
		if ((symbolModule != NULL) && (((ElfDbgModule*)symbolModule)->FindSection(".symtab") != NULL))
		{
			String lldbSymbol = LLDBAddressSymbolName((intptr)sourcePC, false);
			String beefSymbol;
			addr_target offset = 0;
			if (!mDebugTarget->FindSymbolAt(sourcePC, &beefSymbol, &offset))
				beefSymbol = "!Invalid symbol";
			ShadowCompare("addr_symbol", lldbSymbol, beefSymbol);
		}
	}

	ShadowCheckTLS();
}

static bool ShadowSameFile(lldb::SBFileSpec lhs, lldb::SBFileSpec rhs)
{
	const char* lhsName = lhs.GetFilename();
	const char* rhsName = rhs.GetFilename();
	const char* lhsDir = lhs.GetDirectory();
	const char* rhsDir = rhs.GetDirectory();
	return (lhsName != NULL) && (rhsName != NULL) && (strcmp(lhsName, rhsName) == 0) &&
		(strcmp((lhsDir != NULL) ? lhsDir : "", (rhsDir != NULL) ? rhsDir : "") == 0);
}

// LLDB's direct-call targets come from the E8 rel32 bytes, independent of the operand parsing in DecodeInstInfo
void LLDBDebugger::ShadowCheckLineCalls(addr_target pc)
{
	Array<String> beefSites;
	String beefCalls = DbgTargetHost::FindLineCallAddresses((intptr)pc);
	for (auto entry : beefCalls.Split('\n'))
	{
		String site;
		site += entry;
		if (site.StartsWith('-'))
			site.Remove(0, 1);
		int tabIdx = (int)site.IndexOf('\t');
		if (tabIdx != -1)
			site.RemoveToEnd(tabIdx);
		if (site.IsEmpty())
			continue;
		addr_target siteAddr = (addr_target)strtoull(site.c_str(), NULL, 16);
		// Inlined methods are listed at their start, which is not a call instruction
		DbgInstInfo instInfo;
		if ((!mDebugTarget->DecodeInstInfo(siteAddr, NULL, &instInfo)) || (!instInfo.mIsCall))
			continue;
		beefSites.Add(StrFormat("%llx:%llx", (unsigned long long)siteAddr, (unsigned long long)instInfo.mTarget));
	}

	Array<String> lldbSites;
	lldb::SBAddress pcAddr;
	pcAddr.SetLoadAddress((lldb::addr_t)pc, mLLDBTarget);
	lldb::SBLineEntry pcLine = pcAddr.GetLineEntry();
	lldb::SBFunction function = pcAddr.GetFunction();
	if ((!pcLine.IsValid()) || (!function.IsValid()))
		return;
	// A hot-replaced entry is a jump in memory, so the executable's code is decoded from its file bytes
	lldb::SBInstructionList instructions;
	lldb::SBAddress startAddr = function.GetStartAddress();
	lldb::SBSection section = startAddr.GetSection();
	uint64 functionSize = function.GetEndAddress().GetFileAddress() - startAddr.GetFileAddress();
	if ((section.IsValid()) && (HotGetModuleVersion(startAddr.GetModule()) == 0) && (functionSize > 0) && (functionSize < 0x100000))
	{
		lldb::SBData fileData = section.GetSectionData(startAddr.GetFileAddress() - section.GetFileAddress(), functionSize);
		Array<uint8> bytes;
		bytes.Resize((intptr)functionSize);
		lldb::SBError error;
		if (fileData.ReadRawData(error, 0, bytes.mVals, (size_t)functionSize) == (size_t)functionSize)
			instructions = mLLDBTarget.GetInstructions(startAddr, bytes.mVals, (size_t)functionSize);
	}
	if (instructions.GetSize() == 0)
		instructions = function.GetInstructions(mLLDBTarget);
	for (uint32 instIdx = 0; instIdx < instructions.GetSize(); instIdx++)
	{
		lldb::SBInstruction instruction = instructions.GetInstructionAtIndex(instIdx);
		lldb::SBAddress instAddr = instruction.GetAddress();
		lldb::SBLineEntry lineEntry = instAddr.GetLineEntry();
		if ((!lineEntry.IsValid()) || (lineEntry.GetLine() != pcLine.GetLine()) || (!ShadowSameFile(lineEntry.GetFileSpec(), pcLine.GetFileSpec())))
			continue;
		if (instAddr.GetBlock().GetContainingInlinedBlock().IsValid())
			continue;
		lldb::InstructionControlFlowKind controlFlowKind = instruction.GetControlFlowKind(mLLDBTarget);
		if ((controlFlowKind != lldb::eInstructionControlFlowKindCall) && (controlFlowKind != lldb::eInstructionControlFlowKindFarCall))
			continue;

		uint64 siteAddr = instAddr.GetLoadAddress(mLLDBTarget);
		uint64 target = 0;
		lldb::SBData data = instruction.GetData(mLLDBTarget);
		uint8 bytes[5] = { 0 };
		lldb::SBError error;
		if ((data.GetByteSize() == 5) && (data.ReadRawData(error, 0, bytes, 5) == 5) && (bytes[0] == 0xE8))
		{
			int32 rel = 0;
			memcpy(&rel, &bytes[1], 4);
			target = siteAddr + 5 + (int64)rel;
		}
		lldbSites.Add(StrFormat("%llx:%llx", (unsigned long long)siteAddr, (unsigned long long)target));
	}

	auto _Format = [](Array<String>& sites)
	{
		sites.Sort([](const String& lhs, const String& rhs) { return strcmp(lhs.c_str(), rhs.c_str()) < 0; });
		String result;
		for (auto& site : sites)
			result += site + " ";
		return result;
	};
	if (!lldbSites.IsEmpty())
		mShadowQueryCounts["line_calls_nonempty"]++;
	String location = StrFormat("%s:%d ", (pcLine.GetFileSpec().GetFilename() != NULL) ? pcLine.GetFileSpec().GetFilename() : "?", pcLine.GetLine() - 1);
	ShadowCompare("line_calls", location + _Format(lldbSites), location + _Format(beefSites));
}

void LLDBDebugger::ShadowCheckTLS()
{
	if ((mCallStack.IsEmpty()) || (mDebugTarget->mLaunchBinary == NULL))
		return;
	DbgModule* dbgModule = mDebugTarget->mLaunchBinary;
	WdStackFrame* wdStackFrame = mCallStack[0];

	HashSet<String> seenNames;
	for (auto dbgType : dbgModule->mTypes)
	{
		if ((dbgType->mCompileUnit == NULL) || (dbgType->mCompileUnit->mLanguage != DbgLanguage_Beef))
			continue;
		for (auto member : dbgType->mMemberList)
		{
			if ((!member->mIsStatic) || (member->mName == NULL) || (member->mLocationLen <= 0))
				continue;
			uint8 lastOp = member->mLocationData[member->mLocationLen - 1];
			if ((lastOp != DW_OP_GNU_push_tls_address) && (lastOp != DW_OP_form_tls_address))
				continue;

			String qualifiedName = dbgType->ToString(DbgLanguage_Beef);
			qualifiedName.Replace(".", "::");
			qualifiedName += "::";
			qualifiedName += member->mName;
			if (!seenNames.Add(qualifiedName))
				continue;

			String lldbName;
			lldb::SBValueList candidates = mLLDBTarget.FindGlobalVariables(member->mName, 64);
			for (uint32 candidateIdx = 0; candidateIdx < candidates.GetSize(); candidateIdx++)
			{
				const char* candidateName = candidates.GetValueAtIndex(candidateIdx).GetName();
				if ((candidateName != NULL) && (String(candidateName).EndsWith(qualifiedName)))
				{
					lldbName = candidateName;
					break;
				}
			}
			if (lldbName.IsEmpty())
				continue;

			// A target-level SBValue has no thread, so a thread-local is looked up through the stopped thread's frame
			uint64 lldbAddr = mLLDBFrames[0].GetValueForVariablePath(lldbName.c_str()).GetLoadAddress();
			// LLDB's debug info doesn't place statics a hot compile adds, which its evaluator reads through HotFindThreadLocalOffset
			uint64 tlsOffset = 0;
			uint64 blockAddr = 0;
			if ((lldbAddr == LLDB_INVALID_ADDRESS) && (HotFindThreadLocalOffset(lldbName.c_str(), tlsOffset)) && (HotGetTlsBlockAddr(mLLDBFrames[0], blockAddr)))
				lldbAddr = blockAddr + tlsOffset;

			DbgAddrType addrType = DbgAddrType_NoValue;
			addr_target beefAddr = (addr_target)dbgModule->EvaluateLocation(NULL, member->mLocationData, member->mLocationLen, wdStackFrame, &addrType);
			ShadowCompare("tls_addr", StrFormat("%s %llx", qualifiedName.c_str(), (unsigned long long)lldbAddr),
				StrFormat("%s %llx", qualifiedName.c_str(), (unsigned long long)beefAddr));
		}
	}
}

void LLDBDebugger::ShadowCheckBreakpoint(LLDBBreakpoint* bp)
{
	if ((bp->mFilePath.IsEmpty()) || (!bp->mLLDBBreakpoint.IsValid()) || (!bp->mVersionBreakpoints.IsEmpty()) || (bp->mInstrOffset > 0) || (!mLLDBProcess.IsValid()))
		return;
	HostSyncModules();
	if (mDebugTarget == NULL)
		return;

	Array<uint64> lldbAddrs;
	for (uint32 locIdx = 0; locIdx < bp->mLLDBBreakpoint.GetNumLocations(); locIdx++)
	{
		lldb::SBBreakpointLocation loc = bp->mLLDBBreakpoint.GetLocationAtIndex(locIdx);
		if ((!loc.IsValid()) || (!loc.IsEnabled()))
			continue;
		lldb::addr_t loadAddr = loc.GetLoadAddress();
		if (loadAddr == LLDB_INVALID_ADDRESS)
			continue;
		// Windows binds an older hot version only through HotBindBreakpoint, at that version's line
		DbgSubprogram* subprogram = mDebugTarget->FindSubProgram((addr_target)loadAddr, DbgOnDemandKind_LocalOnly);
		if ((subprogram != NULL) && (subprogram->mHotReplaceKind != DbgSubprogram::HotReplaceKind_None))
			continue;
		lldbAddrs.Add((uint64)loadAddr);
	}

	Array<addr_target> boundAddrs;
	DbgSrcFile* srcFile = mDebugTarget->GetSrcFile(bp->mFilePath);
	if (srcFile != NULL)
	{
		int boundLineNum = 0;
		HostBindLineAddresses(srcFile, bp->mRequestedLineNum, bp->mInstrOffset, -1, boundAddrs, boundLineNum);
	}
	Array<uint64> beefAddrs;
	for (auto addr : boundAddrs)
		beefAddrs.Add((uint64)addr);

	auto _Format = [](Array<uint64>& addrs)
	{
		addrs.Sort([](uint64 lhs, uint64 rhs) { return lhs < rhs; });
		String result;
		for (auto addr : addrs)
			result += StrFormat("%llx ", (unsigned long long)addr);
		return result;
	};
	String location = StrFormat("%s:%d ", GetFileName(bp->mFilePath).c_str(), bp->mRequestedLineNum);
	mShadowQueryCounts["breakpoint"]++;

	// Windows binds every run of the line and LLDB one location per function, so only addresses LLDB has and Beef lacks are mismatches
	Array<uint64> missingAddrs;
	Array<uint64> extraAddrs;
	for (auto addr : lldbAddrs)
	{
		if (!beefAddrs.Contains(addr))
			missingAddrs.Add(addr);
	}
	for (auto addr : beefAddrs)
	{
		if (!lldbAddrs.Contains(addr))
			extraAddrs.Add(addr);
	}
	if (!missingAddrs.IsEmpty())
	{
		mShadowMismatchCounts["breakpoint"]++;
		ShadowReportLine(StrFormat("DBGSHADOW breakpoint: lldb=%s beef=%s returned=%s", (location + _Format(lldbAddrs)).c_str(), (location + _Format(beefAddrs)).c_str(), ShadowIsFlipped("breakpoint") ? "beef" : "lldb"));
	}
	else if (!extraAddrs.IsEmpty())
	{
		mShadowExtraCount++;
		ShadowReportLine(StrFormat("DBGSHADOW breakpoint-extra: lldb=%s beef=%s returned=%s", (location + _Format(lldbAddrs)).c_str(), (location + _Format(beefAddrs)).c_str(), ShadowIsFlipped("breakpoint") ? "beef" : "lldb"));
	}
}

static String ShadowEvalLine(const StringImpl& result, int lineIdx)
{
	int start = 0;
	for (int i = 0; i < lineIdx; i++)
	{
		int nl = (int)result.IndexOf('\n', start);
		if (nl == -1)
			return String();
		start = nl + 1;
	}
	int end = (int)result.IndexOf('\n', start);
	if (end == -1)
		end = (int)result.length();
	return String(result.Substring(start, end - start));
}

// Beef groups hex addresses with an apostrophe after a zero-padded high half and pads empty objects with two
// spaces, as the IDE shows them on Windows; LLDB does neither and omits empty braces after a pointer
static String ShadowNormalizeDisplay(const StringImpl& value)
{
	String result;
	for (int i = 0; i < (int)value.length(); i++)
	{
		char c = value[i];
		if ((c == '0') && (i + 1 < (int)value.length()) && (value[i + 1] == 'x'))
		{
			result += "0x";
			i += 2;
			while ((i < (int)value.length()) && ((value[i] == '\'') || (value[i] == '0')))
				i++;
			while ((i < (int)value.length()) && ((isxdigit((uint8)value[i])) || (value[i] == '\'')))
			{
				if (value[i] != '\'')
					result += value[i];
				i++;
			}
			i--;
			continue;
		}
		result += c;
	}
	// LLDB prints a null pointer as "null", Beef as the zero address, which the loop above shortens to "0x"
	for (int nullIdx = (int)result.IndexOf("null"); nullIdx != -1; nullIdx = (int)result.IndexOf("null", nullIdx + 2))
	{
		bool startOk = (nullIdx == 0) || (result[nullIdx - 1] == '=') || (result[nullIdx - 1] == ' ');
		bool endOk = (nullIdx + 4 >= (int)result.length()) || (result[nullIdx + 4] == ' ') || (result[nullIdx + 4] == ',');
		if ((startOk) && (endOk))
		{
			result.Remove(nullIdx, 4);
			result.Insert(nullIdx, "0x");
		}
	}
	// Beef shows a string member's address before the text, as on Windows
	for (int strIdx = (int)result.IndexOf("=0x"); strIdx != -1; strIdx = (int)result.IndexOf("=0x", strIdx + 1))
	{
		int quoteIdx = strIdx + 3;
		while ((quoteIdx < (int)result.length()) && (isxdigit((uint8)result[quoteIdx])))
			quoteIdx++;
		if ((quoteIdx + 1 < (int)result.length()) && (result[quoteIdx] == ' ') && (result[quoteIdx + 1] == '"'))
			result.Remove(strIdx + 1, quoteIdx + 1 - (strIdx + 1));
	}
	// Beef names the method a delegate or function value points to, as on Windows; LLDB's visualizer does not
	// for a delegate and has no symbol for hot-compiled code
	for (int nameIdx = (int)result.IndexOf(" {"); nameIdx != -1; nameIdx = (int)result.IndexOf(" {", nameIdx + 1))
	{
		int parenIdx = (int)result.IndexOf('(', nameIdx);
		int closeIdx = (parenIdx != -1) ? (int)result.IndexOf(")}", parenIdx) : -1;
		if ((closeIdx != -1) && (!result.Substring(nameIdx + 2, parenIdx - nameIdx - 2).Contains(' ')) && (!result.Substring(nameIdx + 2, parenIdx - nameIdx - 2).Contains('=')))
			result.Remove(nameIdx, closeIdx + 2 - nameIdx);
	}
	int funcParenIdx = (int)result.IndexOf('(');
	if ((result.StartsWith("{")) && (result.EndsWith(")}")) && (funcParenIdx != -1) && (!result.Substring(1, funcParenIdx - 1).Contains(' ')))
		result = "{0x}";
	// Beef shows a struct with one member as "{ value }" on every platform; LLDB names the member
	for (int openIdx = (int)result.IndexOf("{ "); openIdx != -1; openIdx = (int)result.IndexOf("{ ", openIdx + 1))
	{
		int closeIdx = (int)result.IndexOf(" }", openIdx + 2);
		if (closeIdx == -1)
			break;
		String inner = result.Substring(openIdx + 2, closeIdx - openIdx - 2);
		int eqIdx = (int)inner.IndexOf('=');
		if ((eqIdx > 1) && (inner[0] == 'm') && (isupper((uint8)inner[1])) && (!inner.Contains(' ')) && (!inner.Contains('{')) && (inner.IndexOf('"') == -1))
			result.Remove(openIdx + 2, eqIdx + 1);
	}
	// Unreadable memory shows as "???" in Beef and "{...}" in LLDB
	result.Replace("{...}", "???");
	// Beef shows an object's address before its visualizer's string, as on Windows
	if ((result.StartsWith("0x")) && (result.Contains(" \"")) && (result.EndsWith("\"")))
		result.Remove(0, result.IndexOf(" \"") + 1);
	// Beef shows the pointee of a pointer member inline, as on Windows; LLDB shows only the address
	for (int memberIdx = (int)result.IndexOf("=0x"); memberIdx != -1; memberIdx = (int)result.IndexOf("=0x", memberIdx + 3))
	{
		int braceIdx = memberIdx + 3;
		while ((braceIdx < (int)result.length()) && (isxdigit((uint8)result[braceIdx])))
			braceIdx++;
		if ((braceIdx + 1 >= (int)result.length()) || (result[braceIdx] != ' ') || (result[braceIdx + 1] != '{'))
			continue;
		int depth = 0;
		int endIdx = braceIdx + 1;
		for (; endIdx < (int)result.length(); endIdx++)
		{
			if (result[endIdx] == '{')
				depth++;
			else if ((result[endIdx] == '}') && (--depth == 0))
				break;
		}
		if (endIdx < (int)result.length())
			result.Remove(braceIdx, endIdx + 1 - braceIdx);
	}
	while (result.Contains("{  }"))
		result.Replace("{  }", "{ }");
	// Beef names a function by its declared parameters, LLDB by their demangled C++ types
	for (int closeIdx = (int)result.IndexOf(")}"); closeIdx != -1; closeIdx = (int)result.IndexOf(")}", closeIdx + 2))
	{
		int openIdx = (int)result.LastIndexOf('(', closeIdx);
		if (openIdx == -1)
			continue;
		result.Remove(openIdx + 1, closeIdx - openIdx - 1);
		closeIdx = openIdx;
	}
	if (result.EndsWith(" { }"))
		result.RemoveToEnd(result.length() - 4);
	return result;
}

// As ScriptManager.Evaluate reads results, but with only the error class kept since the two engines word errors differently
static String ShadowEvalValue(const StringImpl& result)
{
	if (result.StartsWith("!"))
		return "!error";
	return ShadowNormalizeDisplay(ShadowEvalLine(result, 0));
}

static String ShadowMemoryWatch(const StringImpl& result)
{
	if (result.StartsWith("!"))
		return "!error";
	uint64 addr = strtoull(ShadowEvalLine(result, 0).c_str(), NULL, 16);
	return StrFormat("%llx %s", (unsigned long long)addr, ShadowEvalLine(result, 1).c_str());
}

// Calls are never run by the shadow: a second run would repeat their side effects
void LLDBDebugger::ShadowCheckEval(const StringImpl& expr, int callStackIdx, int language, DwEvalExpressionFlags expressionFlags, const StringImpl& lldbResult)
{
	if ((lldbResult.StartsWith("!pending")) || (mDebugTarget == NULL) || (!mHostFramesLive))
	{
		mShadowQueryCounts["eval_skipped"]++;
		return;
	}

	// The IDE evaluates child expressions that LLDB's visualizers wrote, casting raw addresses with C++ pointer
	// semantics; Beef's evaluator writes its own child expressions, so these have no Beef counterpart
	if (expr.Contains("*)0x"))
	{
		mShadowQueryCounts["eval_skipped"]++;
		return;
	}

	// Visualizers.txt asserts LLDB's own range checks on these intrinsics; those lines are rewritten when evaluation moves to Beef
	if ((expr.Contains("__getHighBits")) || (expr.Contains("__clearHighBits")))
	{
		mShadowQueryCounts["eval_skipped"]++;
		return;
	}

	DwEvalExpressionFlags beefFlags = (DwEvalExpressionFlags)(expressionFlags &
		~(DwEvalExpressionFlag_AllowCalls | DwEvalExpressionFlag_AllowSideEffects | DwEvalExpressionFlag_AllowPropertyEval));
	String beefResult = DbgTargetHost::Evaluate(expr, callStackIdx, -1, language, beefFlags);
	if ((beefResult.StartsWith("!pending")) || (beefResult.StartsWith("!sideeffects")) || (beefResult.Contains("\n:sideeffects")))
	{
		mShadowQueryCounts["eval_skipped"]++;
		return;
	}

	String prefix = StrFormat("%s => ", expr.c_str());
	if ((expressionFlags & DwEvalExpressionFlag_MemoryWatch) != 0)
	{
		ShadowCompare("memwatch", prefix + ShadowMemoryWatch(lldbResult), prefix + ShadowMemoryWatch(beefResult));
		return;
	}
	String lldbValue = ShadowEvalValue(lldbResult);
	String beefValue = ShadowEvalValue(beefResult);
	// Beef cuts a long summary short with "...", as on Windows; LLDB shows every member
	if (beefValue.EndsWith("... }"))
	{
		String shownPart = beefValue.Substring(0, beefValue.length() - 5);
		if (lldbValue.StartsWith(shownPart))
			lldbValue = beefValue;
	}
	if (lldbValue != beefValue)
	{
		const char* knownDifference = ShadowKnownEvalDifference(expr, lldbValue, beefValue);
		if (knownDifference != NULL)
		{
			mShadowQueryCounts["eval_known"]++;
			ShadowReportLine(StrFormat("DBGSHADOW eval-known (%s): lldb=%s beef=%s", knownDifference, (prefix + lldbValue).c_str(), (prefix + beefValue).c_str()));
			return;
		}
	}
	ShadowCompare("eval", prefix + lldbValue, prefix + beefValue);
}

static String ShadowEraseSingleValues(const StringImpl& value)
{
	String result = value;
	for (int openIdx = (int)result.IndexOf("={ "); openIdx != -1; openIdx = (int)result.IndexOf("={ ", openIdx + 1))
	{
		int closeIdx = (int)result.IndexOf(" }", openIdx + 2);
		if (closeIdx == -1)
			break;
		if (closeIdx == openIdx + 2)
			continue;
		String inner = result.Substring(openIdx + 3, closeIdx - openIdx - 3);
		if ((!inner.Contains(' ')) && (!inner.Contains('{')))
			result.Remove(openIdx + 3, closeIdx - openIdx - 2);
	}
	return result;
}

// Differences where Beef shows what Windows shows, or a Linux gap listed in pr4-design.md; returns why, or NULL
const char* LLDBDebugger::ShadowKnownEvalDifference(const StringImpl& expr, const StringImpl& lldbValue, const StringImpl& beefValue)
{
	// LLDB sometimes leaves a typed primitive member's braces empty (always with ",refid", in BeefIDE also without)
	if (lldbValue.Contains("={ }"))
	{
		String lldbErased = ShadowEraseSingleValues(lldbValue);
		String beefErased = ShadowEraseSingleValues(beefValue);
		if (beefErased.EndsWith("... }"))
			beefErased.RemoveToEnd(beefErased.length() - 5);
		if (lldbErased.StartsWith(beefErased))
			return "lldb typed primitive";
	}

	// '@' names an earlier local of the same name, as DebugTarget does on Windows; LLDB has no such names
	if ((expr.StartsWith('@')) && (lldbValue == "!error"))
		return "shadowed local";

	// Both sides failed to read part of the value; Beef's ReadTypedValue reads a typed primitive without checking the
	// read on every platform, so Windows shows it as { 0 } as well
	if ((lldbValue.Contains("???")) && (beefValue.Contains("???")))
		return "unreadable memory";

	// Beef applies the System.Event visualizer to an Event member, as on Windows; LLDB shows its raw field
	if (beefValue.Contains("={ data="))
	{
		String beefEvent = beefValue;
		beefEvent.Replace("={ data=", "={ ");
		if (ShadowEraseSingleValues(lldbValue) == ShadowEraseSingleValues(beefEvent))
			return "event visualizer";
	}

	// A thread-local static added by a hot compile is not in the debug info layer yet (pr4-design.md, before the 4d flip)
	String qualifiedName = expr;
	qualifiedName.Replace(".", "::");
	for (auto& kv : mHotSymbols)
	{
		if (!kv.mValue.mIsTLS)
			continue;
		char* demangled = llvm::itaniumDemangle(std::string_view(kv.mKey.c_str(), kv.mKey.length()));
		bool matches = (demangled != NULL) && (StringView(demangled).EndsWith("::" + qualifiedName));
		free(demangled);
		if (matches)
			return "hot thread-local static";
	}
	return NULL;
}

// Beef lists the names used near the stop and LLDB every local, so only names both list are compared
void LLDBDebugger::ShadowCheckAutoExpressions(int callStackIdx, uint64 memoryRangeStart, uint64 memoryRangeLen, const StringImpl& lldbResult)
{
	if ((mDebugTarget == NULL) || (!mHostFramesLive))
		return;
	String beefResult = DbgTargetHost::GetAutoExpressions(callStackIdx, memoryRangeStart, memoryRangeLen);
	Dictionary<String, String> beefEntries;
	for (auto entryView : beefResult.Split('\n'))
	{
		String entry;
		entry += entryView;
		if (!entry.StartsWith("&"))
			continue;
		int tabIdx = (int)entry.IndexOf('\t');
		if (tabIdx == -1)
			continue;
		beefEntries[String(entry.Substring(0, tabIdx))] = String(entry.Substring(tabIdx + 1));
	}
	String lldbEntries = lldbResult;
	for (auto entryView : lldbEntries.Split('\n'))
	{
		String entry;
		entry += entryView;
		int tabIdx = (int)entry.IndexOf('\t');
		if ((!entry.StartsWith("&")) || (tabIdx == -1))
			continue;
		String name = entry.Substring(0, tabIdx);
		String* beefEntry = NULL;
		if (!beefEntries.TryGetValue(name, &beefEntry))
			continue;
		ShadowCompare("autos_expr", entry, name + "\t" + *beefEntry);
	}
}

void LLDBDebugger::ShadowWriteReport()
{
	if (!mShadowEnabled)
		return;

	int queries = 0;
	int mismatches = 0;
	for (auto& kv : mShadowQueryCounts)
		queries += kv.mValue;
	for (auto& kv : mShadowMismatchCounts)
		mismatches += kv.mValue;
	if ((queries == 0) && (mHostUnsupportedCount == 0))
		return;

	String report;
	for (auto& line : mShadowMismatchLines)
		report += line + "\n";
	for (auto& kv : mShadowQueryCounts)
	{
		int queryMismatches = 0;
		mShadowMismatchCounts.TryGetValue(kv.mKey, &queryMismatches);
		report += StrFormat("DBGSHADOW query %s queries=%d mismatches=%d source=%s\n", kv.mKey.c_str(), kv.mValue, queryMismatches, ShadowIsFlipped(kv.mKey.c_str()) ? "beef" : "lldb");
	}
	for (auto& kv : mHostUnsupportedCounts)
		report += StrFormat("DBGSHADOW unsupported %s count=%d\n", kv.mKey.c_str(), kv.mValue);
	report += StrFormat("DBGSHADOW queries=%d mismatches=%d extra=%d unsupported=%d\n", queries, mismatches, mShadowExtraCount, mHostUnsupportedCount);
	LLDBLog("%s", report.c_str());

	if (!mShadowReportPath.IsEmpty())
	{
		FILE* fp = fopen(mShadowReportPath.c_str(), "a");
		if (fp != NULL)
		{
			fwrite(report.c_str(), 1, report.length(), fp);
			fclose(fp);
		}
	}

	mShadowQueryCounts.Clear();
	mShadowMismatchCounts.Clear();
	mShadowMismatchLines.Clear();
	mHostUnsupportedCount = 0;
	mHostUnsupportedCounts.Clear();
	mShadowExtraCount = 0;
}

#endif
