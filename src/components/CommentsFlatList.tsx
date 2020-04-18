import { FlatList, ListRenderItem, RefreshControl } from "react-native";
import { FlatHNComment } from "../common/types";
import { default as React, useCallback } from "react";
import { CommentWithChildren } from "./CommentWithChildren";
import { backgroundDark, padding } from "../common/vars";
import { CommentsListItemHeader } from "./CommentsListItemHeader";
import { HNStoryWithComments } from "../fetchers/fetchCommentsForItem";

interface Props {
  story: HNStoryWithComments;
  comments: FlatHNComment[];
  isRefreshing: boolean;
  refetch: () => void;
}

export const CommentsFlatList: React.FC<Props> = ({
  story,
  comments,
  isRefreshing,
  refetch
}) => {
  const user: string = story?.by?.id ?? "deleted";

  const renderItem: ListRenderItem<FlatHNComment> = useCallback(
    ({ item }) => (
      <CommentWithChildren
        op={user}
        comment={item.comment}
        depth={item.depth}
      />
    ),
    [user]
  );

  return (
    <FlatList
      style={{ backgroundColor: backgroundDark }}
      data={comments}
      contentContainerStyle={{ paddingBottom: padding * 3 }}
      refreshControl={
        <RefreshControl
          refreshing={isRefreshing}
          onRefresh={refetch}
          tintColor={"white"}
        />
      }
      ListHeaderComponent={<CommentsListItemHeader story={story} />}
      keyExtractor={item => String(item.comment.id)}
      renderItem={renderItem}
    />
  );
};
