import { createClient } from "urql";

export const urqlClient = createClient({
  url: "https://www.graphqlhub.com/graphql"
});
