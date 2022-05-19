#include <iostream>
#include <vector>
#include "rapidcsv.h"

int main(int argc, char **argv)
{
  rapidcsv::Document doc(argv[1], rapidcsv::LabelParams(-1, -1));

  std::vector<float> close = doc.GetColumn<float>(0);
  std::cout << "Read " << close.size() << " values." << std::endl;

  long long volume = doc.GetCell<long long>(0, 0);
  std::cout << "Volume " << volume << " on 1,2." << std::endl;
  return 0;
}