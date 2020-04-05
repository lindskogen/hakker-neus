import { HNStory } from "../common/types";
import { request } from "graphql-request";
import { GQL_ENDPOINT } from "../lib/graphql-endpoint";
import { useMemo, useState } from "react";
import { useInfiniteQuery } from "react-query";
import { flatMap } from "lodash-es";

const newsListQuery = `
  query Query($limit: Int!, $offset: Int!) {
    hn {
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
  }
`;

export interface Paginated<T> {
  data: T;
  nextPage: number;
}

const STEP = 40;

export const fetchNewsList = (
  key: string,
  cursor: number = 0
): Promise<Paginated<HNStory[]>> =>
  request(GQL_ENDPOINT, newsListQuery, {
    limit: STEP,
    offset: STEP * cursor
  }).then(data => ({ data: data.hn.topStories, nextPage: cursor + 1 }));

export const useNewsList = () => {
  const [isRefetching, setRefetching] = useState(false);
  const { refetch, data: stories, fetchMore, isFetchingMore } = useInfiniteQuery(
    "news-list",
    fetchNewsList,
    {
      suspense: true,
      refetchOnMount: false,
      staleTime: 1000,
      onSettled: () => setRefetching(false),
      refetchOnWindowFocus: false,
      getFetchMore: (lastPage: any) => lastPage.nextPage
    }
  );

  const onRefresh = () => {
    setRefetching(true);
    refetch();
  };

  const flattenedStories = useMemo(() => flatMap(stories, page => page.data), [
    stories
  ]);

  return {
    isRefetching,
    onRefresh,
    stories: flattenedStories,
    fetchMore,
    isFetchingMore
  };
};
