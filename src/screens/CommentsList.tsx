import * as React from "react";
import { useCallback, useEffect, useLayoutEffect, useState } from "react";
import { FlatList, ListRenderItem, RefreshControl, View } from "react-native";
import { NavigationScreenProp } from "react-navigation";
import { HNComment, HNStory } from "../common/types";
import { backgroundDark } from "../common/vars";
import { CommentsListItemHeader } from "../components/CommentsListItemHeader";
import { CommentWithChildren } from "../components/CommentWithChildren";
import { Loader } from "../components/Loader";
import { useQuery } from "react-query";
import {
  fetchCommentsForItem,
  HNStoryWithComments
} from "../fetchers/fetchCommentsForItem";

export const CommentsList: React.FC<{
  navigation: NavigationScreenProp<{}, { id: string; story?: HNStory }>;
}> = ({ navigation }) => {
  const { id } = navigation.state.params!;

  const [mounted, setMounted] = useState(false);

  const { data: story, status, error, refetch, ...rest } = useQuery<
    HNStoryWithComments,
    any
  >(
    ["comments", { id }],
    // @ts-ignore
    fetchCommentsForItem
  );

  useEffect(() => {
    setMounted(true);
  }, []);

  console.log(status, rest);

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

  if (!story || !mounted) {
    return (
      <View style={{ flex: 1 }}>
        {navigation.state.params!.story && (
          <CommentsListItemHeader
            navigation={navigation}
            story={navigation.state.params!.story}
          />
        )}
        <Loader backgroundColor={backgroundDark} />
      </View>
    );
  }

  const comments = story.kids.filter(
    (kid: HNComment | null) => kid && !!kid.text
  ) as HNComment[];

  return (
    <FlatList
      style={{ backgroundColor: backgroundDark }}
      data={comments}
      refreshControl={
        <RefreshControl
          refreshing={status === "loading"}
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
