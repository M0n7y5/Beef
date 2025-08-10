#include "BeefySysLib/Common.h"
#include "BfAst.h"
#include "BfSystem.h"
#include "BfCompiler.h"
#include "BfExprEvaluator.h"

NS_BF_BEGIN

class BfModule;
class BfMethodMatcher;

enum BfConstResolveFlags
{
	BfConstResolveFlag_None = 0,
	BfConstResolveFlag_ExplicitCast = 1,
	BfConstResolveFlag_NoCast = 2,
	BfConstResolveFlag_AllowSoftFail = 4,
	BfConstResolveFlag_ActualizeValues = 8,
	BfConstResolveFlag_NoActualizeValues = 0x10,
	BfConstResolveFlag_ArrayInitSize = 0x20,
	BfConstResolveFlag_AllowGlobalVariable = 0x40,
	BfConstResolveFlag_NoConversionOperator = 0x80
};

class BfConstResolver : public BfExprEvaluator
{
public:
	bool mIsInvalidConstExpr;

public:
	virtual bool CheckAllowValue(const BfTypedValue& typedValue, BfAstNode* refNode) override;

public:
	BfConstResolver(BfModule* bfModule);

	BfTypedValue Resolve(BfExpression* expr, BfType* wantType = NULL, BfConstResolveFlags flags = BfConstResolveFlag_None);
	bool PrepareMethodArguments(BfAstNode* targetSrc, BfMethodMatcher* methodMatcher, Array<BfIRValue>& llvmArgs);
};

NS_BF_END