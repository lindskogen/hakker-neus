import {
  FlatList,
  ListRenderItem,
  RefreshControl,
  StyleSheet,
} from "react-native";
import { FlatHNComment } from "../common/types";
import { default as React, useMemo } from "react";
import { CommentWithChildren } from "./CommentWithChildren";
import { backgroundDark, padding } from "../common/vars";
import { CommentsListItemHeader } from "./CommentsListItemHeader";
import { HNStoryWithComments } from "../fetchers/fetchCommentsForItem";
import { OpContextProvider } from "./OpContext";

interface Props {
  story: HNStoryWithComments;
  comments: FlatHNComment[];
  isRefreshing: boolean;
  refetch: () => void;
}

const renderItem: ListRenderItem<FlatHNComment> = ({ item }) => (
  <CommentWithChildren comment={item.comment} depth={item.depth} />
);

export const CommentsFlatList: React.FC<Props> = ({
  story,
  comments,
  isRefreshing,
  refetch,
}) => {
  const listHeaderComponent = useMemo(
    () => <CommentsListItemHeader story={story} />,
    [story]
  );

  const refreshControl = useMemo(
    () => (
      <RefreshControl
        refreshing={isRefreshing}
        onRefresh={refetch}
        tintColor={"white"}
      />
    ),
    [isRefreshing, refetch]
  );

  return (
    <OpContextProvider value={story?.by?.id ?? "deleted"}>
      <FlatList<FlatHNComment>
        style={styles.scrollView}
        data={comments}
        contentContainerStyle={styles.container}
        refreshControl={refreshControl}
        ListHeaderComponent={listHeaderComponent}
        keyExtractor={keyExtractor}
        renderItem={renderItem}
      />
    </OpContextProvider>
  );
};

const styles = StyleSheet.create({
  scrollView: { backgroundColor: backgroundDark },
  container: { paddingBottom: padding * 3 },
});

const keyExtractor = (item: FlatHNComment) => String(item.comment.id);
