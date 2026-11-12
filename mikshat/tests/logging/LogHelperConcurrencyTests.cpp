#include "base/logging.hpp"

#include <atomic>
#include <barrier>
#include <cmath>
#include <iostream>
#include <locale>
#include <mutex>
#include <set>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

int main(int argc, char ** argv)
{
  bool const serializeControl = argc == 2 && std::string(argv[1]) == "--serialize-control";
  if (argc > 1 && !serializeControl)
    return 2;

  std::locale::global(std::locale::classic());
  constexpr unsigned threadCount = 32;
  constexpr unsigned repetitions = 1000;
  auto & helper = base::LogHelper::Instance();
  int const mainThreadID = helper.GetThreadID();
  std::barrier start(threadCount);
  std::mutex controlMutex;
  std::atomic<unsigned> failures{0};
  std::vector<int> threadIDs(threadCount);
  std::vector<std::thread> workers;

  for (unsigned index = 0; index < threadCount; ++index)
  {
    workers.emplace_back([&, index] {
      start.arrive_and_wait();
      int firstID = 0;
      for (unsigned iteration = 0; iteration < repetitions; ++iteration)
      {
        int id;
        std::ostringstream output;
        {
          // This option is a diagnostic baseline control only. The fixed-source
          // regression runs WITHOUT a caller lock, like the iOS logger.
          std::unique_lock lock(controlMutex, std::defer_lock);
          if (serializeControl)
            lock.lock();
          helper.WriteProlog(output, base::LINFO);
          id = helper.GetThreadID();
        }

        if (iteration == 0)
          firstID = id;
        if (id <= 0 || id != firstID || id == mainThreadID)
          ++failures;

        char level = 0, opening = 0, closing = 0;
        int formattedID = 0;
        double elapsed = -1;
        std::istringstream prolog(output.str());
        if (!(prolog >> level >> opening >> formattedID >> closing >> elapsed) ||
            level != 'I' || opening != '(' || closing != ')' || formattedID != id ||
            !std::isfinite(elapsed) || elapsed < 0)
          ++failures;
        prolog >> std::ws;
        if (!prolog.eof())
          ++failures;
      }
      threadIDs[index] = firstID;
    });
  }
  for (auto & worker : workers)
    worker.join();

  std::set<int> const uniqueIDs(threadIDs.begin(), threadIDs.end());
  if (mainThreadID <= 0 || uniqueIDs.size() != threadCount || failures != 0)
  {
    std::cerr << "FAIL: unique worker IDs=" << uniqueIDs.size()
              << ", invalid/stale prologs or IDs=" << failures << '\n';
    return 1;
  }
  std::cout << "PASS: " << threadCount * repetitions
            << " actual production WriteProlog calls; positive, stable, unique thread IDs and valid prologs; "
            << "external serialization=" << serializeControl << '\n';
}
