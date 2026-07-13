/*
 * mayhem/fuzzcsv.cpp — libFuzzer harness for rapidcsv (in-process port of the
 * archived file-input fuzzcsv CLI, which parsed argv[1] as a headerless CSV and
 * read a float column + a long long cell).
 *
 * The CLI form aborted on every malformed input via uncaught rapidcsv exceptions
 * (std::invalid_argument from the numeric converters), drowning real defects, so
 * the same code path is driven in-process here: parse the input as a Document,
 * then exercise the read API (GetColumn/GetRow/GetCell with several converter
 * types) with expected parse/convert exceptions caught. Memory-safety bugs and
 * UB inside rapidcsv.h still abort via ASan/UBSan (halting).
 */
#include <cstdint>
#include <cstddef>
#include <sstream>
#include <string>
#include <vector>

#include "rapidcsv.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
  if (size < 1)
    return 0;

  // First byte selects parse options; the rest is the CSV payload.
  const uint8_t opts = data[0];
  const char sep = (opts & 1) ? ';' : ',';
  const bool trim = opts & 2;
  const bool quoted = !(opts & 4);
  const int colHdr = (opts & 8) ? 0 : -1;
  const int rowHdr = (opts & 16) ? 0 : -1;

  const std::string payload(reinterpret_cast<const char *>(data + 1), size - 1);
  std::istringstream stream(payload);

  try
  {
    rapidcsv::Document doc(stream,
                           rapidcsv::LabelParams(colHdr, rowHdr),
                           rapidcsv::SeparatorParams(sep, trim, true, quoted),
                           rapidcsv::ConverterParams(),
                           rapidcsv::LineReaderParams());

    const size_t rows = doc.GetRowCount();
    const size_t cols = doc.GetColumnCount();

    for (size_t c = 0; c < cols && c < 8; ++c)
    {
      try { (void)doc.GetColumn<std::string>(c); } catch (...) {}
      try { (void)doc.GetColumn<float>(c); } catch (...) {}
    }
    for (size_t r = 0; r < rows && r < 8; ++r)
    {
      try { (void)doc.GetRow<std::string>(r); } catch (...) {}
      for (size_t c = 0; c < cols && c < 8; ++c)
      {
        try { (void)doc.GetCell<long long>(c, r); } catch (...) {}
        try { (void)doc.GetCell<double>(c, r); } catch (...) {}
      }
    }

    // Exercise the writer path too: serialize the parsed document back out.
    std::ostringstream out;
    doc.Save(out);
  }
  catch (...)
  {
    // Malformed CSV / bad conversions throw — expected, not a defect.
  }

  return 0;
}
