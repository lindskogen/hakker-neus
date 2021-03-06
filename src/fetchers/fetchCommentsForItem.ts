import { HNComment, HNStory } from "../common/types";
import { request } from "graphql-request";
import { GQL_ENDPOINT } from "../lib/graphql-endpoint";
import { useQuery } from "react-query";
import { useCallback, useState } from "react";

const commentsQuery = `
  query CommentsQuery($id: Int!) {
    item(id: $id) {
      id
      type
      descendants
      title
      kids {
        ...Comment
        kids {
          ...Comment
          kids {
            ...Comment
            kids {
              ...Comment
              kids {
                ...Comment
              }
            }
          }
        }
      }
      by {
        id
      }
      text
      url
      score
    }
  }

  fragment Comment on HackerNewsItem {
    id
    type
    by {
      id
    }
    text
    timeISO
  }
`;

export interface HNStoryWithComments extends HNStory {
  kids: (HNComment | null)[];
}

export const fetchCommentsForItem = (
  id: string
): Promise<HNStoryWithComments> =>
  request(GQL_ENDPOINT, commentsQuery, { id: parseInt(id, 10) }).then(
    (data) => data.item
  );

export const useHNItemWithComments = (id: string) => {
  const [isRefreshing, setRefreshing] = useState(false);
  const { data: story, isFetching, refetch } = useQuery<HNStoryWithComments>(
    ["comments", id],
    ({ queryKey }) => fetchCommentsForItem(queryKey[1]),
    {
      onSettled: () => setRefreshing(false),
      refetchOnWindowFocus: false,
    }
  );

  const onRefresh = useCallback(() => {
    setRefreshing(true);
    refetch();
  }, [refetch]);

  return {
    onRefresh,
    isRefreshing,
    story,
    isFetching,
  };
};
