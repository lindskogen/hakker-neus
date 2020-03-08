import { FlatList, ListRenderItem, RefreshControl } from "react-native";
import { FlatHNComment, HNStory } from "../common/types";
import { default as React, useCallback } from "react";
import { CommentWithChildren } from "./CommentWithChildren";
import { backgroundDark, padding } from "../common/vars";
import { CommentsListItemHeader } from "./CommentsListItemHeader";
import { HNStoryWithComments } from "../fetchers/fetchCommentsForItem";
import { StackNavigationProp } from "react-navigation-stack/lib/typescript/src/vendor/types";

interface Props {
  story: HNStoryWithComments;
  comments: FlatHNComment[];
  navigation: StackNavigationProp<{}, { id: string; story?: HNStory }>;
  isRefreshing: boolean;
  refetch: () => void;
}

export const CommentsFlatList: React.FC<Props> = ({
  navigation,
  story,
  comments,
  isRefreshing,
  refetch
}) => {
  const user: string = story?.by.id ?? "undefined";

  const renderItem: ListRenderItem<FlatHNComment> = useCallback(
    ({ item }) => (
      <CommentWithChildren
        op={user}
        comment={item.comment}
        depth={item.depth}
        navigation={navigation}
      />
    ),
    [user, navigation]
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
      ListHeaderComponent={
        <CommentsListItemHeader navigation={navigation} story={story} />
      }
      keyExtractor={item => String(item.comment.id)}
      renderItem={renderItem}
    />
  );
};
