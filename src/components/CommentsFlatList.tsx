import { FlatList, ListRenderItem, RefreshControl } from "react-native";
import { HNComment, HNStory } from "../common/types";
import { default as React, useCallback } from "react";
import { CommentWithChildren } from "./CommentWithChildren";
import { backgroundDark, padding } from "../common/vars";
import { CommentsListItemHeader } from "./CommentsListItemHeader";
import { HNStoryWithComments } from "../fetchers/fetchCommentsForItem";
import { NavigationScreenProp } from "react-navigation";

interface Props {
  story: HNStoryWithComments;
  comments: HNComment[];
  navigation: NavigationScreenProp<{}, { id: string; story?: HNStory }>;
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

  const renderItem: ListRenderItem<HNComment> = useCallback(
    ({ item }) => (
      <CommentWithChildren
        op={user}
        comment={item}
        depth={0}
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
          onRefresh={() => refetch()}
          tintColor={"white"}
        />
      }
      ListHeaderComponent={
        <CommentsListItemHeader navigation={navigation} story={story} />
      }
      keyExtractor={item => String(item.id)}
      renderItem={renderItem}
    />
  );
};
