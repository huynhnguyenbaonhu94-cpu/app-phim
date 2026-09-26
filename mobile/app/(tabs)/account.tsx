import { ScrollView, Text, View } from "react-native";
import { Ionicons } from "@expo/vector-icons";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { C, GlassCard, GlassMenu, ScreenAtmosphere, SectionTitle, styles, useAutoHideTabBar } from "@/ui";

export default function Account() {
  const insets = useSafeAreaInsets();
  const onScroll = useAutoHideTabBar();
  return <View style={[styles.screen, { overflow: "hidden" }]}>
    <ScreenAtmosphere />
    <ScrollView onScroll={onScroll} scrollEventThrottle={16} style={{ flex: 1, backgroundColor: "transparent" }} contentContainerStyle={[styles.content, { paddingTop: insets.top + 10 }]} showsVerticalScrollIndicator={false}>
      <View style={styles.header}><View><Text style={styles.brand}>TÀI KHOẢN</Text><Text style={{ color: C.muted, fontSize: 10, marginTop: 4 }}>Không gian cá nhân của bạn</Text></View><GlassMenu /></View>
      <SectionTitle eyebrow="CINEMORA · CÁ NHÂN HÓA" title="Không gian của bạn" />
      <GlassCard style={{ padding: 22, borderRadius: 26 }}>
        <View style={accountStyles.icon}><Ionicons name="person-outline" size={24} color={C.accent} /></View>
        <Text style={accountStyles.title}>Mở khóa trải nghiệm riêng</Text>
        <Text style={accountStyles.copy}>Đăng nhập sẽ sớm có mặt để bạn lưu phim yêu thích và tiếp tục xem trên các thiết bị.</Text>
        <View style={accountStyles.status}><View style={accountStyles.statusDot} /><Text style={accountStyles.statusText}>TÍNH NĂNG ĐANG ĐƯỢC HOÀN THIỆN</Text></View>
      </GlassCard>
      <Text style={accountStyles.sectionLabel}>SẮP CÓ TRÊN CINEMORA</Text>
      <View style={accountStyles.featureList}>
        <Feature icon="heart-outline" title="Danh sách yêu thích" detail="Lưu lại phim bạn muốn xem." />
        <Feature icon="time-outline" title="Lịch sử xem" detail="Tiếp tục đúng nơi bạn đã dừng." />
        <Feature icon="phone-portrait-outline" title="Đồng bộ thiết bị" detail="Trải nghiệm liền mạch mọi lúc." />
      </View>
      <Text style={accountStyles.footnote}>Thông tin tài khoản chỉ hiển thị khi tính năng đăng nhập được kết nối.</Text>
    </ScrollView>
  </View>;
}

function Feature({ icon, title, detail }: { icon: keyof typeof Ionicons.glyphMap; title: string; detail: string }) {
  return <View style={accountStyles.feature}><View style={accountStyles.featureIcon}><Ionicons name={icon} size={19} color={C.accent} /></View><View style={{ flex: 1 }}><Text style={accountStyles.featureTitle}>{title}</Text><Text style={accountStyles.featureDetail}>{detail}</Text></View><Ionicons name="chevron-forward" size={16} color={C.muted} /></View>;
}

const accountStyles = {
  icon: { width: 58, height: 58, borderRadius: 21, alignItems: "center" as const, justifyContent: "center" as const, backgroundColor: "rgba(197,210,255,0.12)", borderWidth: 1, borderColor: "rgba(225,232,255,0.2)" },
  title: { color: C.text, fontSize: 20, lineHeight: 26, fontWeight: "900" as const, marginTop: 16 },
  copy: { color: C.muted, fontSize: 12, lineHeight: 19, marginTop: 7 },
  status: { minHeight: 34, alignSelf: "flex-start" as const, flexDirection: "row" as const, alignItems: "center" as const, gap: 7, paddingHorizontal: 11, borderRadius: 20, marginTop: 17, backgroundColor: "rgba(197,210,255,0.08)", borderWidth: 1, borderColor: "rgba(225,232,255,0.12)" },
  statusDot: { width: 6, height: 6, borderRadius: 3, backgroundColor: C.accent },
  statusText: { color: C.accent, fontSize: 8, fontWeight: "900" as const, letterSpacing: 0.7 },
  sectionLabel: { color: C.muted, fontSize: 9, fontWeight: "900" as const, letterSpacing: 1.7, marginTop: 30, marginBottom: 9 },
  featureList: { overflow: "hidden" as const, borderRadius: 22, backgroundColor: "rgba(255,255,255,0.04)", borderWidth: 1, borderColor: "rgba(225,232,255,0.12)" },
  feature: { minHeight: 74, flexDirection: "row" as const, alignItems: "center" as const, gap: 13, paddingHorizontal: 14, borderBottomWidth: 1, borderBottomColor: "rgba(225,232,255,0.08)" },
  featureIcon: { width: 40, height: 40, borderRadius: 14, alignItems: "center" as const, justifyContent: "center" as const, backgroundColor: "rgba(197,210,255,0.09)" },
  featureTitle: { color: C.text, fontSize: 12, fontWeight: "800" as const },
  featureDetail: { color: C.muted, fontSize: 10, marginTop: 3 },
  footnote: { color: C.muted, fontSize: 10, lineHeight: 16, marginTop: 17 },
};
