import { HNStory } from "../common/types";
import { request } from "graphql-request";
import { GQL_ENDPOINT } from "../lib/graphql-endpoint";

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

export const fetchNewsList = (key: string, cursor: number = 0): Promise<HNStory[]> =>
  request(GQL_ENDPOINT, newsListQuery, { limit: 20, offset: 20 * cursor }).then(data => data.hn.topStories);