import * as React from "react";
import { NavigationScreenProp } from "react-navigation";
import { CommentsFlatList } from "../components/CommentsFlatList";
import { noop } from "lodash-es";
import { flattenComments } from "./CommentsList";

export const CommentsSink2: React.FC<{
  navigation: NavigationScreenProp<{}, {}>;
}> = ({ navigation }) => {
  return (
    <CommentsFlatList
      comments={flattenComments(require("./fullcomments.json"))}
      isRefreshing={false}
      story={{
        id: "234",
        type: "comment",
        text: "text",
        by: { id: "testing" },
        kids: [],
        descendants: 2,
        title: "title",
        score: 2
      }}
      navigation={navigation}
      refetch={noop}
    />
  );
};
