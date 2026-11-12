#import "storage/background_downloading/downloader_adapter_ios.h"

#import "platform/background_downloader_ios.h"

#include "storage/downloader.hpp"

#include "base/assert.hpp"
#include "base/file_name_utils.hpp"

#include <memory>
#include <utility>

@interface NSError (ToDownloaderError)

- (downloader::DownloadStatus)toDownloaderError;

@end

@implementation NSError (ToDownloaderError)

- (downloader::DownloadStatus)toDownloaderError
{
  return self.code == NSURLErrorFileDoesNotExist ? downloader::DownloadStatus::FileNotFound
                                                 : downloader::DownloadStatus::Failed;
}

@end

namespace storage
{

void BackgroundDownloaderAdapter::Remove(CountryId const & countryId)
{
  m_downloadGenerations.erase(countryId);
  MapFilesDownloader::Remove(countryId);

  if (!m_queue.Contains(countryId))
    return;

  BackgroundDownloader * downloader = [BackgroundDownloader sharedBackgroundMapDownloader];
  auto const taskIdentifier = m_queue.GetTaskInfoForCountryId(countryId);
  if (taskIdentifier)
    [downloader cancelTaskWithIdentifier:*taskIdentifier];
  m_queue.Remove(countryId);
}

void BackgroundDownloaderAdapter::Clear()
{
  m_downloadGenerations.clear();
  MapFilesDownloader::Clear();

  BackgroundDownloader * downloader = [BackgroundDownloader sharedBackgroundMapDownloader];
  [downloader clear];
  m_queue.Clear();
}

QueueInterface const & BackgroundDownloaderAdapter::GetQueue() const
{
  if (m_queue.IsEmpty())
    return MapFilesDownloader::GetQueue();

  return m_queue;
}

void BackgroundDownloaderAdapter::Download(QueuedCountry && queuedCountry)
{
  if (!IsDownloadingAllowed())
  {
    queuedCountry.OnDownloadFinished(downloader::DownloadStatus::Failed);
    return;
  }

  auto const countryId = queuedCountry.GetCountryId();
  auto urls = MakeUrlList(queuedCountry);
  if (urls.empty())
  {
    queuedCountry.OnDownloadFinished(downloader::DownloadStatus::Failed);
    return;
  }
  // Get urls order from worst to best.
  std::reverse(urls.begin(), urls.end());
  auto const path = queuedCountry.GetFileDownloadPath();

  // The order is important here: add to the queue first, notify start downloading then.
  // Infinite recursion possible here, otherwise:
  // OnStartDownloading -> NotifyStatusChanged -> processCountryEvent -> configDialog (?!)
  // -> downloadNode for the same country if autodownload enabled -> Download.
  auto const generation = ++m_nextDownloadGeneration;
  m_downloadGenerations[countryId] = generation;
  auto const isCurrentAttempt = [this, &countryId, generation]
  {
    auto const it = m_downloadGenerations.find(countryId);
    return it != m_downloadGenerations.end() && it->second == generation;
  };
  m_queue.Append(QueuedCountry(queuedCountry));
  if (!isCurrentAttempt())
    return;

  queuedCountry.OnStartDownloading();
  if (!isCurrentAttempt())
    return;

  DownloadFromLastUrl(countryId, path, std::move(urls), generation);
}

void BackgroundDownloaderAdapter::DownloadFromLastUrl(CountryId const & countryId, std::string const & downloadPath,
                                                      std::vector<std::string> && urls, uint64_t generation)
{
  if (urls.empty())
    return;

  NSURL * url = [NSURL URLWithString:@(urls.back().c_str())];
  assert(url != nil);
  urls.pop_back();

  auto onFinish = [this, countryId, downloadPath, generation, urls = std::move(urls)](NSError * error) mutable
  {
    downloader::DownloadStatus status = error ? [error toDownloaderError] : downloader::DownloadStatus::Completed;

    auto const it = m_downloadGenerations.find(countryId);
    if (it == m_downloadGenerations.end() || it->second != generation)
      return;

    if (status == downloader::DownloadStatus::Failed && !urls.empty())
    {
      DownloadFromLastUrl(countryId, downloadPath, std::move(urls), generation);
    }
    else
    {
      auto const country = m_queue.GetCountryById(countryId);
      m_queue.Remove(countryId);
      m_downloadGenerations.erase(countryId);
      country.OnDownloadFinished(status);
    }
  };

  auto onProgress = [this, countryId, generation](int64_t totalWritten, int64_t totalExpected)
  {
    auto const it = m_downloadGenerations.find(countryId);
    if (it == m_downloadGenerations.end() || it->second != generation)
      return;

    auto const & country = m_queue.GetCountryById(countryId);
    country.OnDownloadProgress({totalWritten, totalExpected});
  };

  BackgroundDownloader * downloader = [BackgroundDownloader sharedBackgroundMapDownloader];
  NSUInteger taskId = [downloader downloadWithUrl:url
                                         filePath:@(downloadPath.c_str())
                                       completion:onFinish
                                         progress:onProgress];

  m_queue.SetTaskInfoForCountryId(countryId, taskId);
}

std::unique_ptr<MapFilesDownloader> GetDownloader()
{
  return std::make_unique<BackgroundDownloaderAdapter>();
}

}  // namespace storage
