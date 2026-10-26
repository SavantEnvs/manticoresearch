// Copy of src/fuzzer/fuzzer.cpp (qfuzzer) with the per-exec __lsan_do_recoverable_leak_check()/assert
// removed: leak detection is disabled at build time (mayhem/lsan_off.cc) and the check cost a full
// heap scan per input. Everything else (QueryParser fixture, Transform, entry point) is unchanged.
#include <cstdint>
#include <cstddef>
#include <array>

#include "dict/dict_base.h"
#include "schema/schema.h"
#include "sphinxquery/sphinxquery.h"
#include "sphinxquery/xqparser.h"
#include "std/string.h"
#include "std/stringbuilder.h"
#include "tokenizer/tokenizer.h"
#include "sphinxint.h"

class CSphDummyIndex : public CSphIndexStub
{
public:
  SmallStringHash_T<int> m_hHits;

  CSphDummyIndex ()
    : CSphIndexStub ( nullptr, nullptr )
  { }

  bool FillKeywords ( CSphVector<CSphKeywordInfo> & dKeywords ) const override;
};

struct CKeywordHits
{
  const char * m_szKeyword;
  int m_iHits;
};


class QueryParser
{
protected:

  void SetUp ()
  {
    tSchema.AddField ( "title" );
    tSchema.AddField ( "body" );

    TokenizerRefPtr_c pBase = Tokenizer::Detail::CreateUTF8Tokenizer();
    CSphTokenizerSettings tTokenizerSetup;
    tTokenizerSetup.m_iMinWordLen = 2;
    pBase->Setup ( tTokenizerSetup );
    pTokenizer = sphCloneAndSetupQueryTokenizer ( pBase, true, false, false );

    CSphDictSettings tDictSettings;
    tDictSettings.SetDictFormat ( DictFormat_e::CRC );
    pDict = sphCreateDictionaryCRC ( tDictSettings, NULL, pTokenizer, "query", false, 32, nullptr, sError );
    constexpr CKeywordHits dPseudoHits[] = { { "aaa", 0 }, { "bbb", 0 }, { "ccc", 35 }, { "ddd", 63 }, { "eee", 2445 } };

    for ( const CKeywordHits & tHit: dPseudoHits )
      tIndex.m_hHits.Add ( tHit.m_iHits, tHit.m_szKeyword );
  }

public:
  QueryParser ()
  {
    SetUp();
  }

  void Transform ( const char * szQuery ) const;

  DictRefPtr_c pDict;
  CSphSchema tSchema;
  CSphIndexSettings tTmpSettings;
  CSphDummyIndex tIndex;
  TokenizerRefPtr_c pTokenizer;
  CSphString sError;
};


bool CSphDummyIndex::FillKeywords ( CSphVector <CSphKeywordInfo> & dKeywords ) const
{
	ARRAY_FOREACH ( i, dKeywords )
	{
		int * pDocs = m_hHits ( dKeywords[i].m_sTokenized );
		dKeywords[i].m_iDocs = pDocs ? *pDocs : 0;
	}

	return true;
}

void QueryParser::Transform ( const char * szQuery ) const
{

  XQQuery_t tQuery;
  if (!sphParseExtendedQuery ( tQuery, szQuery, nullptr, pTokenizer, &tSchema, pDict, tTmpSettings, nullptr ))
    return;

  if (!tQuery.m_pRoot)
    return;

  TransformExtendedQueryArgs_t tTranformArgs { true, tQuery.m_bNeedPhraseTransform, &tIndex };
	sphTransformExtendedQuery ( &tQuery.m_pRoot, tTmpSettings, tQuery.m_sParseError, tTranformArgs, tQuery.m_sParseWarning );
}

void get_case ( StringBuilder_c & cBuilder, const uint8_t * Data, size_t Size )
{
  cBuilder.Clear();
  cBuilder << Str_t { (const char *) Data, Size };
}

extern
"C"
int LLVMFuzzerTestOneInput ( const uint8_t * Data, size_t Size )
{
  StringBuilder_c cBuilder;
  static QueryParser transformer;

  get_case ( cBuilder, Data, Size );
  transformer.Transform ( cBuilder.cstr() );
  return 0;
}
