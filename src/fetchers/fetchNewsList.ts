import { HNStory } from "../common/types";
import { request } from "graphql-request";
import { GQL_ENDPOINT } from "../lib/graphql-endpoint";
import { useCallback, useMemo, useState } from "react";
import { useInfiniteQuery } from "react-query";
import { flatMap, uniqBy } from "lodash-es";
import { isDefined } from "../lib/isDefined";

const newsListQuery = `
  query Query($limit: Int!, $offset: Int!) {
    topStories(limit: $limit, offset: $offset) {
      id
      descendants
      type
      title
      by {
        id
      }
      text
      url
      score
    }
  }
`;

export interface Paginated<T> {
  data: T;
  nextPage: number;
}

const STEP = 40;

export const fetchNewsList = (cursor: number): Promise<Paginated<HNStory[]>> =>
  request(GQL_ENDPOINT, newsListQuery, {
    limit: STEP,
    offset: STEP * cursor,
  }).then((data) => ({
    data: data.topStories.filter(isDefined),
    nextPage: cursor + 1,
  }));

export const useNewsList = () => {
  const [isRefetching, setRefetching] = useState(false);
  const {
    refetch,
    data: stories,
    fetchNextPage,
    isFetchingNextPage,
    remove,
  } = useInfiniteQuery(
    "news-list",
    ({ pageParam = 0 }) => fetchNewsList(pageParam),
    {
      suspense: !isRefetching,
      refetchOnMount: false,
      keepPreviousData: true,
      onSettled: () => setRefetching(false),
      refetchOnWindowFocus: false,
      getNextPageParam: (lastPage: Paginated<HNStory[]>) => lastPage.nextPage,
    }
  );

  const onRefresh = useCallback(() => {
    setRefetching(true);
    remove();
    refetch();
  }, [remove, refetch]);

  const flattenedStories = useMemo(
    () =>
      uniqBy(
        flatMap(stories?.pages, (page) => page.data),
        (s) => s.id
      ),
    [stories]
  );

  return {
    isRefetching,
    onRefresh,
    stories: flattenedStories,
    fetchMore: useCallback(() => fetchNextPage(), [fetchNextPage]),
    isFetchingMore: isFetchingNextPage,
  };
};
