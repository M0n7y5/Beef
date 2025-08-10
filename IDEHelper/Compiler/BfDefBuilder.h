#include "BeefySysLib/Common.h"
#include "BfAst.h"
#include "BfSystem.h"

NS_BF_BEGIN

// This is the first pass through our ASTs, builds up Def structures in BfSystem
//  so when we go to compile we'll be able to resolve references

class BfResolvePassData;

class BfDefBuilder : public BfStructuralVisitor
{
public:
	struct NamespaceState
	{
		BfAtomComposite mNamespace;
		int mNamespaceSearchCount;

		NamespaceState()
		{
			mNamespaceSearchCount = -1;
		}
	};

public:
	BfSource* mCurSource;
	BfSystem* mSystem;
	BfPassInstance* mPassInstance;
	BfTypeDef* mCurTypeDef;
	BfTypeDef* mCurDeclaringTypeDef;
	BfTypeDef* mCurActualTypeDef;
	bool mFullRefresh;
	bool mIsComptime;
	BfResolvePassData* mResolvePassData;
	BfAtomComposite mNamespace;
	Array<BfAtomComposite> mNamespaceSearch;
	Array<BfTypeReference*> mStaticSearch;
	Array<BfTypeReference*> mInternalAccessSet;
	HashContext* mFullHashCtx;
	HashContext* mSignatureHashCtx;

	Array<NamespaceState> mFileLevelNamespaceState;
	int mNamespaceBlockDepth;

public:
	void ParseGenericParams(BfGenericParamsDeclaration* genericParamsDecl, BfGenericConstraintsDeclaration* genericConstraints, Array<BfGenericParamDef*>& genericParams, Array<BfExternalConstraintDef>* externConstraintDefs, int outerGenericSize, bool isInGeneric);
	BfProtection GetProtection(BfAstNode* protectionNode);
	bool WantsNode(BfAstNode* wholeNode, BfAstNode* startNode = NULL, int addLen = 0);
	//static BfNamedTypeReference* AllocTypeReference(BfSource* bfSource, const StringImpl& typeName);
	//static BfResolvedTypeReference* AllocTypeReference(BfSource* bfSource, BfType* type);
	static BfFieldDef* AddField(BfTypeDef* typeDef, BfTypeReference* typeRef, const StringImpl& name);
	static BfMethodDef* AddMethod(BfTypeDef* typeDef, BfMethodType methodType, BfProtection protection, bool isStatic, const StringImpl& name, bool addedAfterEmit = false);
	static BfMethodDef* AddDtor(BfTypeDef* typeDef);
	static void AddDynamicCastMethods(BfTypeDef* typeDef, bool needsDynamicCastMethods);
	static void AddParam(BfMethodDef* methodDef, BfTypeReference* typeRef, const StringImpl& paramName);
	BfTypeDef* ComparePrevTypeDef(BfTypeDef* prevTypeDef, BfTypeDef* checkTypeDef);
	void FinishTypeDef(bool wantsToString);
	void ParseAttributes(BfAttributeDirective* attributes, BfMethodDef* methodDef, bool checkReturnType = true);
	void ParseAttributes(BfAttributeDirective* attributes, BfTypeDef* typeDef);
	BfMethodDef* CreateMethodDef(BfMethodDeclaration* methodDecl, BfMethodDef* outerMethodDef = NULL);
	BfError* Fail(const StringImpl& errorStr, BfAstNode* refNode);
	void SetNamespaceState(const NamespaceState& namespaceState);

public:
	BfDefBuilder(BfSystem* bfSystem);
	~BfDefBuilder();

	void Process(BfPassInstance* passInstance, BfSource* bfSource, bool fullRefresh);
	void RemoveDefsFrom(BfSource* bfSource);

	virtual void Visit(BfIdentifierNode* identifier) override;
	virtual void Visit(BfMethodDeclaration* methodDeclaration) override;
	virtual void Visit(BfConstructorDeclaration* ctorDeclaration) override;
	virtual void Visit(BfPropertyDeclaration* propertyDeclaration) override;
	virtual void Visit(BfFieldDeclaration* fieldDeclaration) override;
	virtual void Visit(BfEnumCaseDeclaration* enumCaseDeclaration) override;
	virtual void Visit(BfTypeDeclaration* typeDeclaration) override;
	virtual void Visit(BfUsingDirective* usingDirective) override;
	virtual void Visit(BfUsingModDirective* usingDirective) override;
	virtual void Visit(BfNamespaceDeclaration* namespaceDeclaration) override;
	virtual void Visit(BfBlock* block) override;
	virtual void Visit(BfRootNode* rootNode) override;
};

NS_BF_END