import { Client } from "bugsnag-react-native";

export const bugsnag = new Client(process.env["BUGSNAG_API_KEY"]);
