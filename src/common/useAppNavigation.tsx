import { useNavigation } from "@react-navigation/native";
import { StackNavigationProp } from "@react-navigation/stack";
import { RootStackParamList } from "../../App";

export const useAppNavigation = () =>
  useNavigation<StackNavigationProp<RootStackParamList>>();
