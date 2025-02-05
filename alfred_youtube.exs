
#!/usr/bin/env elixir

Mix.install([
  {:google_api_you_tube, "~> 0.53"},
  {:jason, "~> 1.4"},
  {:number, "~> 1.0"},
  {:mint, "~> 1.0"},
  {:tesla, "~> 1.13"},
  {:timex, "~> 3.7"}
])

defmodule ImageDownloader do
  defp client do
    middleware = [
      {Tesla.Middleware.Retry,
       delay: 500,
       max_retries: 10,
       max_delay: 4_000,
       should_retry: fn
         {:ok, %{status: status}}, _env, _context when status in [400, 500] -> true
         {:ok, _reason}, _env, _context -> false
         {:error, _reason}, %Tesla.Env{method: :post}, _context -> false
         {:error, _reason}, %Tesla.Env{method: :put}, %{retries: 2} -> false
         {:error, _reason}, _env, _context -> true
       end}
    ]

    Tesla.client(middleware, adapter())
  end

  defp adapter, do: Tesla.Adapter.Mint

  def download(url) do
    case Tesla.get(client(), url) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        save_to_temp(body, get_filename(url))

      {:ok, %Tesla.Env{status: status_code}} ->
        IO.puts("Failed to download image. Status code: #{status_code}")

      {:error, reason} ->
        IO.puts("Error: #{reason}")
    end
  end

  defp save_to_temp(image_data, filename) do
    temp_dir = System.tmp_dir!()
    file_path = Path.join(temp_dir, filename)

    case File.write(file_path, image_data) do
      :ok ->
        file_path

      {:error, reason} ->
        IO.puts("Failed to save image: #{reason}")
    end
  end

  defp get_filename(url) do
    paths =
      url
      |> String.split("/")

    video_id = paths |> Enum.at(-2)
    "#{video_id}.jpg"
  end
end

defmodule YoutubeSearch do
  alias GoogleApi.YouTube.V3.Api.Search
  alias GoogleApi.YouTube.V3.Api.Videos
  alias GoogleApi.YouTube.V3.Connection
  alias GoogleApi.YouTube.V3.Model.ResourceId
  alias GoogleApi.YouTube.V3.Model.SearchListResponse
  alias GoogleApi.YouTube.V3.Model.SearchResult
  alias GoogleApi.YouTube.V3.Model.SearchResultSnippet
  alias GoogleApi.YouTube.V3.Model.Thumbnail
  alias GoogleApi.YouTube.V3.Model.ThumbnailDetails
  alias GoogleApi.YouTube.V3.Model.Video
  alias GoogleApi.YouTube.V3.Model.VideoListResponse
  alias GoogleApi.YouTube.V3.Model.VideoStatistics

  def build_connection, do: Connection.new()

  def search(query) do
    conn = build_connection()

    case conn |> req_search_api(query) do
      {:ok, %SearchListResponse{items: items}} ->
        alfred_items =
          items
          |> Enum.map(&map_to_alfred_item(&1))

        video_ids = alfred_items |> Enum.map(& &1.uid)
        video_statistics = conn |> fetch_video_statistics(video_ids)

        alfred_items =
          alfred_items
          |> Enum.map(fn %{uid: video_id, subtitle: subtitle} = item ->
            video_statistic = video_statistics |> Map.get(video_id) |> Number.SI.number_to_si()
            item |> Map.put(:subtitle, subtitle <> " • #{video_statistic} views")
          end)

        %{
          rerun: 1,
          items: alfred_items
        }

      {:error, error} ->
        IO.inspect(error)
    end
  end

  def req_search_api(conn, query) do
    conn
    |> Search.youtube_search_list(
      ["snippet"],
      q: query,
      key: fetch_api_key(),
      maxResults: 12,
      type: ["video"]
    )
  end

  def map_to_alfred_item(%SearchResult{
        id: %ResourceId{videoId: video_id},
        snippet: %SearchResultSnippet{
          title: title,
          thumbnails: %ThumbnailDetails{default: %Thumbnail{url: thumbnail_url}},
          channelTitle: channel_title,
          publishedAt: published_at
        }
      }) do
    thumbnail_tmp_path = ImageDownloader.download(thumbnail_url)

    relative_published_at =
      Timex.Format.DateTime.Formatters.Relative.format!(published_at, "{relative}")

    subtitle = "#{channel_title}  • #{relative_published_at}"

    %{
      uid: video_id,
      title: title,
      subtitle: subtitle,
      arg: "https://www.youtube.com/watch?v=#{video_id}",
      icon: %{
        path: thumbnail_tmp_path
      }
    }
  end

  def fetch_video_statistics(conn, video_ids) do
    {:ok, %VideoListResponse{items: items}} =
      Videos.youtube_videos_list(conn, ["statistics"],
        id: video_ids,
        key: fetch_api_key()
      )

    items
    |> Enum.reduce(%{}, fn %Video{
                             id: video_id,
                             statistics: %VideoStatistics{viewCount: view_count}
                           },
                           statistics ->
      statistics |> Map.put(video_id, view_count)
    end)
  end

  def fetch_api_key, do: System.get_env("LB_API_KEY")
end

[query | _] = System.argv()

query |> YoutubeSearch.search() |> Jason.encode!() |> IO.puts()
outubeSearch.search("lenka") |> Jason.encode!() |> IO.puts()
