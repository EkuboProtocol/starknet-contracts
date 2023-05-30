// Returns the u256 representing 2**n
fn exp2(n: u8) -> u256 {
    if (n > 127) {
        if (n > 191) {
            if (n > 223) {
                if (n > 239) {
                    if (n > 247) {
                        if (n > 251) {
                            if (n > 253) {
                                if (n == 254) {
                                    return u256 {
                                        high: 0x40000000000000000000000000000000, low: 0x0
                                    };
                                } else {
                                    return u256 {
                                        high: 0x80000000000000000000000000000000, low: 0x0
                                    };
                                }
                            } else {
                                if (n == 252) {
                                    return u256 {
                                        high: 0x10000000000000000000000000000000, low: 0x0
                                    };
                                } else {
                                    return u256 {
                                        high: 0x20000000000000000000000000000000, low: 0x0
                                    };
                                }
                            }
                        } else {
                            if (n > 249) {
                                if (n == 250) {
                                    return u256 {
                                        high: 0x4000000000000000000000000000000, low: 0x0
                                    };
                                } else {
                                    return u256 {
                                        high: 0x8000000000000000000000000000000, low: 0x0
                                    };
                                }
                            } else {
                                if (n == 248) {
                                    return u256 {
                                        high: 0x1000000000000000000000000000000, low: 0x0
                                    };
                                } else {
                                    return u256 {
                                        high: 0x2000000000000000000000000000000, low: 0x0
                                    };
                                }
                            }
                        }
                    } else {
                        if (n > 243) {
                            if (n > 245) {
                                if (n == 246) {
                                    return u256 {
                                        high: 0x400000000000000000000000000000, low: 0x0
                                    };
                                } else {
                                    return u256 {
                                        high: 0x800000000000000000000000000000, low: 0x0
                                    };
                                }
                            } else {
                                if (n == 244) {
                                    return u256 {
                                        high: 0x100000000000000000000000000000, low: 0x0
                                    };
                                } else {
                                    return u256 {
                                        high: 0x200000000000000000000000000000, low: 0x0
                                    };
                                }
                            }
                        } else {
                            if (n > 241) {
                                if (n == 242) {
                                    return u256 { high: 0x40000000000000000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x80000000000000000000000000000, low: 0x0 };
                                }
                            } else {
                                if (n == 240) {
                                    return u256 { high: 0x10000000000000000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x20000000000000000000000000000, low: 0x0 };
                                }
                            }
                        }
                    }
                } else {
                    if (n > 231) {
                        if (n > 235) {
                            if (n > 237) {
                                if (n == 238) {
                                    return u256 { high: 0x4000000000000000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x8000000000000000000000000000, low: 0x0 };
                                }
                            } else {
                                if (n == 236) {
                                    return u256 { high: 0x1000000000000000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x2000000000000000000000000000, low: 0x0 };
                                }
                            }
                        } else {
                            if (n > 233) {
                                if (n == 234) {
                                    return u256 { high: 0x400000000000000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x800000000000000000000000000, low: 0x0 };
                                }
                            } else {
                                if (n == 232) {
                                    return u256 { high: 0x100000000000000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x200000000000000000000000000, low: 0x0 };
                                }
                            }
                        }
                    } else {
                        if (n > 227) {
                            if (n > 229) {
                                if (n == 230) {
                                    return u256 { high: 0x40000000000000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x80000000000000000000000000, low: 0x0 };
                                }
                            } else {
                                if (n == 228) {
                                    return u256 { high: 0x10000000000000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x20000000000000000000000000, low: 0x0 };
                                }
                            }
                        } else {
                            if (n > 225) {
                                if (n == 226) {
                                    return u256 { high: 0x4000000000000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x8000000000000000000000000, low: 0x0 };
                                }
                            } else {
                                if (n == 224) {
                                    return u256 { high: 0x1000000000000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x2000000000000000000000000, low: 0x0 };
                                }
                            }
                        }
                    }
                }
            } else {
                if (n > 207) {
                    if (n > 215) {
                        if (n > 219) {
                            if (n > 221) {
                                if (n == 222) {
                                    return u256 { high: 0x400000000000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x800000000000000000000000, low: 0x0 };
                                }
                            } else {
                                if (n == 220) {
                                    return u256 { high: 0x100000000000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x200000000000000000000000, low: 0x0 };
                                }
                            }
                        } else {
                            if (n > 217) {
                                if (n == 218) {
                                    return u256 { high: 0x40000000000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x80000000000000000000000, low: 0x0 };
                                }
                            } else {
                                if (n == 216) {
                                    return u256 { high: 0x10000000000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x20000000000000000000000, low: 0x0 };
                                }
                            }
                        }
                    } else {
                        if (n > 211) {
                            if (n > 213) {
                                if (n == 214) {
                                    return u256 { high: 0x4000000000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x8000000000000000000000, low: 0x0 };
                                }
                            } else {
                                if (n == 212) {
                                    return u256 { high: 0x1000000000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x2000000000000000000000, low: 0x0 };
                                }
                            }
                        } else {
                            if (n > 209) {
                                if (n == 210) {
                                    return u256 { high: 0x400000000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x800000000000000000000, low: 0x0 };
                                }
                            } else {
                                if (n == 208) {
                                    return u256 { high: 0x100000000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x200000000000000000000, low: 0x0 };
                                }
                            }
                        }
                    }
                } else {
                    if (n > 199) {
                        if (n > 203) {
                            if (n > 205) {
                                if (n == 206) {
                                    return u256 { high: 0x40000000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x80000000000000000000, low: 0x0 };
                                }
                            } else {
                                if (n == 204) {
                                    return u256 { high: 0x10000000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x20000000000000000000, low: 0x0 };
                                }
                            }
                        } else {
                            if (n > 201) {
                                if (n == 202) {
                                    return u256 { high: 0x4000000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x8000000000000000000, low: 0x0 };
                                }
                            } else {
                                if (n == 200) {
                                    return u256 { high: 0x1000000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x2000000000000000000, low: 0x0 };
                                }
                            }
                        }
                    } else {
                        if (n > 195) {
                            if (n > 197) {
                                if (n == 198) {
                                    return u256 { high: 0x400000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x800000000000000000, low: 0x0 };
                                }
                            } else {
                                if (n == 196) {
                                    return u256 { high: 0x100000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x200000000000000000, low: 0x0 };
                                }
                            }
                        } else {
                            if (n > 193) {
                                if (n == 194) {
                                    return u256 { high: 0x40000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x80000000000000000, low: 0x0 };
                                }
                            } else {
                                if (n == 192) {
                                    return u256 { high: 0x10000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x20000000000000000, low: 0x0 };
                                }
                            }
                        }
                    }
                }
            }
        } else {
            if (n > 159) {
                if (n > 175) {
                    if (n > 183) {
                        if (n > 187) {
                            if (n > 189) {
                                if (n == 190) {
                                    return u256 { high: 0x4000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x8000000000000000, low: 0x0 };
                                }
                            } else {
                                if (n == 188) {
                                    return u256 { high: 0x1000000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x2000000000000000, low: 0x0 };
                                }
                            }
                        } else {
                            if (n > 185) {
                                if (n == 186) {
                                    return u256 { high: 0x400000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x800000000000000, low: 0x0 };
                                }
                            } else {
                                if (n == 184) {
                                    return u256 { high: 0x100000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x200000000000000, low: 0x0 };
                                }
                            }
                        }
                    } else {
                        if (n > 179) {
                            if (n > 181) {
                                if (n == 182) {
                                    return u256 { high: 0x40000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x80000000000000, low: 0x0 };
                                }
                            } else {
                                if (n == 180) {
                                    return u256 { high: 0x10000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x20000000000000, low: 0x0 };
                                }
                            }
                        } else {
                            if (n > 177) {
                                if (n == 178) {
                                    return u256 { high: 0x4000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x8000000000000, low: 0x0 };
                                }
                            } else {
                                if (n == 176) {
                                    return u256 { high: 0x1000000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x2000000000000, low: 0x0 };
                                }
                            }
                        }
                    }
                } else {
                    if (n > 167) {
                        if (n > 171) {
                            if (n > 173) {
                                if (n == 174) {
                                    return u256 { high: 0x400000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x800000000000, low: 0x0 };
                                }
                            } else {
                                if (n == 172) {
                                    return u256 { high: 0x100000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x200000000000, low: 0x0 };
                                }
                            }
                        } else {
                            if (n > 169) {
                                if (n == 170) {
                                    return u256 { high: 0x40000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x80000000000, low: 0x0 };
                                }
                            } else {
                                if (n == 168) {
                                    return u256 { high: 0x10000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x20000000000, low: 0x0 };
                                }
                            }
                        }
                    } else {
                        if (n > 163) {
                            if (n > 165) {
                                if (n == 166) {
                                    return u256 { high: 0x4000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x8000000000, low: 0x0 };
                                }
                            } else {
                                if (n == 164) {
                                    return u256 { high: 0x1000000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x2000000000, low: 0x0 };
                                }
                            }
                        } else {
                            if (n > 161) {
                                if (n == 162) {
                                    return u256 { high: 0x400000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x800000000, low: 0x0 };
                                }
                            } else {
                                if (n == 160) {
                                    return u256 { high: 0x100000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x200000000, low: 0x0 };
                                }
                            }
                        }
                    }
                }
            } else {
                if (n > 143) {
                    if (n > 151) {
                        if (n > 155) {
                            if (n > 157) {
                                if (n == 158) {
                                    return u256 { high: 0x40000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x80000000, low: 0x0 };
                                }
                            } else {
                                if (n == 156) {
                                    return u256 { high: 0x10000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x20000000, low: 0x0 };
                                }
                            }
                        } else {
                            if (n > 153) {
                                if (n == 154) {
                                    return u256 { high: 0x4000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x8000000, low: 0x0 };
                                }
                            } else {
                                if (n == 152) {
                                    return u256 { high: 0x1000000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x2000000, low: 0x0 };
                                }
                            }
                        }
                    } else {
                        if (n > 147) {
                            if (n > 149) {
                                if (n == 150) {
                                    return u256 { high: 0x400000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x800000, low: 0x0 };
                                }
                            } else {
                                if (n == 148) {
                                    return u256 { high: 0x100000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x200000, low: 0x0 };
                                }
                            }
                        } else {
                            if (n > 145) {
                                if (n == 146) {
                                    return u256 { high: 0x40000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x80000, low: 0x0 };
                                }
                            } else {
                                if (n == 144) {
                                    return u256 { high: 0x10000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x20000, low: 0x0 };
                                }
                            }
                        }
                    }
                } else {
                    if (n > 135) {
                        if (n > 139) {
                            if (n > 141) {
                                if (n == 142) {
                                    return u256 { high: 0x4000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x8000, low: 0x0 };
                                }
                            } else {
                                if (n == 140) {
                                    return u256 { high: 0x1000, low: 0x0 };
                                } else {
                                    return u256 { high: 0x2000, low: 0x0 };
                                }
                            }
                        } else {
                            if (n > 137) {
                                if (n == 138) {
                                    return u256 { high: 0x400, low: 0x0 };
                                } else {
                                    return u256 { high: 0x800, low: 0x0 };
                                }
                            } else {
                                if (n == 136) {
                                    return u256 { high: 0x100, low: 0x0 };
                                } else {
                                    return u256 { high: 0x200, low: 0x0 };
                                }
                            }
                        }
                    } else {
                        if (n > 131) {
                            if (n > 133) {
                                if (n == 134) {
                                    return u256 { high: 0x40, low: 0x0 };
                                } else {
                                    return u256 { high: 0x80, low: 0x0 };
                                }
                            } else {
                                if (n == 132) {
                                    return u256 { high: 0x10, low: 0x0 };
                                } else {
                                    return u256 { high: 0x20, low: 0x0 };
                                }
                            }
                        } else {
                            if (n > 129) {
                                if (n == 130) {
                                    return u256 { high: 0x4, low: 0x0 };
                                } else {
                                    return u256 { high: 0x8, low: 0x0 };
                                }
                            } else {
                                if (n == 128) {
                                    return u256 { high: 0x1, low: 0x0 };
                                } else {
                                    return u256 { high: 0x2, low: 0x0 };
                                }
                            }
                        }
                    }
                }
            }
        }
    } else {
        if (n > 63) {
            if (n > 95) {
                if (n > 111) {
                    if (n > 119) {
                        if (n > 123) {
                            if (n > 125) {
                                if (n == 126) {
                                    return u256 {
                                        high: 0x0, low: 0x40000000000000000000000000000000
                                    };
                                } else {
                                    return u256 {
                                        high: 0x0, low: 0x80000000000000000000000000000000
                                    };
                                }
                            } else {
                                if (n == 124) {
                                    return u256 {
                                        high: 0x0, low: 0x10000000000000000000000000000000
                                    };
                                } else {
                                    return u256 {
                                        high: 0x0, low: 0x20000000000000000000000000000000
                                    };
                                }
                            }
                        } else {
                            if (n > 121) {
                                if (n == 122) {
                                    return u256 {
                                        high: 0x0, low: 0x4000000000000000000000000000000
                                    };
                                } else {
                                    return u256 {
                                        high: 0x0, low: 0x8000000000000000000000000000000
                                    };
                                }
                            } else {
                                if (n == 120) {
                                    return u256 {
                                        high: 0x0, low: 0x1000000000000000000000000000000
                                    };
                                } else {
                                    return u256 {
                                        high: 0x0, low: 0x2000000000000000000000000000000
                                    };
                                }
                            }
                        }
                    } else {
                        if (n > 115) {
                            if (n > 117) {
                                if (n == 118) {
                                    return u256 {
                                        high: 0x0, low: 0x400000000000000000000000000000
                                    };
                                } else {
                                    return u256 {
                                        high: 0x0, low: 0x800000000000000000000000000000
                                    };
                                }
                            } else {
                                if (n == 116) {
                                    return u256 {
                                        high: 0x0, low: 0x100000000000000000000000000000
                                    };
                                } else {
                                    return u256 {
                                        high: 0x0, low: 0x200000000000000000000000000000
                                    };
                                }
                            }
                        } else {
                            if (n > 113) {
                                if (n == 114) {
                                    return u256 { high: 0x0, low: 0x40000000000000000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x80000000000000000000000000000 };
                                }
                            } else {
                                if (n == 112) {
                                    return u256 { high: 0x0, low: 0x10000000000000000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x20000000000000000000000000000 };
                                }
                            }
                        }
                    }
                } else {
                    if (n > 103) {
                        if (n > 107) {
                            if (n > 109) {
                                if (n == 110) {
                                    return u256 { high: 0x0, low: 0x4000000000000000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x8000000000000000000000000000 };
                                }
                            } else {
                                if (n == 108) {
                                    return u256 { high: 0x0, low: 0x1000000000000000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x2000000000000000000000000000 };
                                }
                            }
                        } else {
                            if (n > 105) {
                                if (n == 106) {
                                    return u256 { high: 0x0, low: 0x400000000000000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x800000000000000000000000000 };
                                }
                            } else {
                                if (n == 104) {
                                    return u256 { high: 0x0, low: 0x100000000000000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x200000000000000000000000000 };
                                }
                            }
                        }
                    } else {
                        if (n > 99) {
                            if (n > 101) {
                                if (n == 102) {
                                    return u256 { high: 0x0, low: 0x40000000000000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x80000000000000000000000000 };
                                }
                            } else {
                                if (n == 100) {
                                    return u256 { high: 0x0, low: 0x10000000000000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x20000000000000000000000000 };
                                }
                            }
                        } else {
                            if (n > 97) {
                                if (n == 98) {
                                    return u256 { high: 0x0, low: 0x4000000000000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x8000000000000000000000000 };
                                }
                            } else {
                                if (n == 96) {
                                    return u256 { high: 0x0, low: 0x1000000000000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x2000000000000000000000000 };
                                }
                            }
                        }
                    }
                }
            } else {
                if (n > 79) {
                    if (n > 87) {
                        if (n > 91) {
                            if (n > 93) {
                                if (n == 94) {
                                    return u256 { high: 0x0, low: 0x400000000000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x800000000000000000000000 };
                                }
                            } else {
                                if (n == 92) {
                                    return u256 { high: 0x0, low: 0x100000000000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x200000000000000000000000 };
                                }
                            }
                        } else {
                            if (n > 89) {
                                if (n == 90) {
                                    return u256 { high: 0x0, low: 0x40000000000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x80000000000000000000000 };
                                }
                            } else {
                                if (n == 88) {
                                    return u256 { high: 0x0, low: 0x10000000000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x20000000000000000000000 };
                                }
                            }
                        }
                    } else {
                        if (n > 83) {
                            if (n > 85) {
                                if (n == 86) {
                                    return u256 { high: 0x0, low: 0x4000000000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x8000000000000000000000 };
                                }
                            } else {
                                if (n == 84) {
                                    return u256 { high: 0x0, low: 0x1000000000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x2000000000000000000000 };
                                }
                            }
                        } else {
                            if (n > 81) {
                                if (n == 82) {
                                    return u256 { high: 0x0, low: 0x400000000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x800000000000000000000 };
                                }
                            } else {
                                if (n == 80) {
                                    return u256 { high: 0x0, low: 0x100000000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x200000000000000000000 };
                                }
                            }
                        }
                    }
                } else {
                    if (n > 71) {
                        if (n > 75) {
                            if (n > 77) {
                                if (n == 78) {
                                    return u256 { high: 0x0, low: 0x40000000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x80000000000000000000 };
                                }
                            } else {
                                if (n == 76) {
                                    return u256 { high: 0x0, low: 0x10000000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x20000000000000000000 };
                                }
                            }
                        } else {
                            if (n > 73) {
                                if (n == 74) {
                                    return u256 { high: 0x0, low: 0x4000000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x8000000000000000000 };
                                }
                            } else {
                                if (n == 72) {
                                    return u256 { high: 0x0, low: 0x1000000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x2000000000000000000 };
                                }
                            }
                        }
                    } else {
                        if (n > 67) {
                            if (n > 69) {
                                if (n == 70) {
                                    return u256 { high: 0x0, low: 0x400000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x800000000000000000 };
                                }
                            } else {
                                if (n == 68) {
                                    return u256 { high: 0x0, low: 0x100000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x200000000000000000 };
                                }
                            }
                        } else {
                            if (n > 65) {
                                if (n == 66) {
                                    return u256 { high: 0x0, low: 0x40000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x80000000000000000 };
                                }
                            } else {
                                if (n == 64) {
                                    return u256 { high: 0x0, low: 0x10000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x20000000000000000 };
                                }
                            }
                        }
                    }
                }
            }
        } else {
            if (n > 31) {
                if (n > 47) {
                    if (n > 55) {
                        if (n > 59) {
                            if (n > 61) {
                                if (n == 62) {
                                    return u256 { high: 0x0, low: 0x4000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x8000000000000000 };
                                }
                            } else {
                                if (n == 60) {
                                    return u256 { high: 0x0, low: 0x1000000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x2000000000000000 };
                                }
                            }
                        } else {
                            if (n > 57) {
                                if (n == 58) {
                                    return u256 { high: 0x0, low: 0x400000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x800000000000000 };
                                }
                            } else {
                                if (n == 56) {
                                    return u256 { high: 0x0, low: 0x100000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x200000000000000 };
                                }
                            }
                        }
                    } else {
                        if (n > 51) {
                            if (n > 53) {
                                if (n == 54) {
                                    return u256 { high: 0x0, low: 0x40000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x80000000000000 };
                                }
                            } else {
                                if (n == 52) {
                                    return u256 { high: 0x0, low: 0x10000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x20000000000000 };
                                }
                            }
                        } else {
                            if (n > 49) {
                                if (n == 50) {
                                    return u256 { high: 0x0, low: 0x4000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x8000000000000 };
                                }
                            } else {
                                if (n == 48) {
                                    return u256 { high: 0x0, low: 0x1000000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x2000000000000 };
                                }
                            }
                        }
                    }
                } else {
                    if (n > 39) {
                        if (n > 43) {
                            if (n > 45) {
                                if (n == 46) {
                                    return u256 { high: 0x0, low: 0x400000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x800000000000 };
                                }
                            } else {
                                if (n == 44) {
                                    return u256 { high: 0x0, low: 0x100000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x200000000000 };
                                }
                            }
                        } else {
                            if (n > 41) {
                                if (n == 42) {
                                    return u256 { high: 0x0, low: 0x40000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x80000000000 };
                                }
                            } else {
                                if (n == 40) {
                                    return u256 { high: 0x0, low: 0x10000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x20000000000 };
                                }
                            }
                        }
                    } else {
                        if (n > 35) {
                            if (n > 37) {
                                if (n == 38) {
                                    return u256 { high: 0x0, low: 0x4000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x8000000000 };
                                }
                            } else {
                                if (n == 36) {
                                    return u256 { high: 0x0, low: 0x1000000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x2000000000 };
                                }
                            }
                        } else {
                            if (n > 33) {
                                if (n == 34) {
                                    return u256 { high: 0x0, low: 0x400000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x800000000 };
                                }
                            } else {
                                if (n == 32) {
                                    return u256 { high: 0x0, low: 0x100000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x200000000 };
                                }
                            }
                        }
                    }
                }
            } else {
                if (n > 15) {
                    if (n > 23) {
                        if (n > 27) {
                            if (n > 29) {
                                if (n == 30) {
                                    return u256 { high: 0x0, low: 0x40000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x80000000 };
                                }
                            } else {
                                if (n == 28) {
                                    return u256 { high: 0x0, low: 0x10000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x20000000 };
                                }
                            }
                        } else {
                            if (n > 25) {
                                if (n == 26) {
                                    return u256 { high: 0x0, low: 0x4000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x8000000 };
                                }
                            } else {
                                if (n == 24) {
                                    return u256 { high: 0x0, low: 0x1000000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x2000000 };
                                }
                            }
                        }
                    } else {
                        if (n > 19) {
                            if (n > 21) {
                                if (n == 22) {
                                    return u256 { high: 0x0, low: 0x400000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x800000 };
                                }
                            } else {
                                if (n == 20) {
                                    return u256 { high: 0x0, low: 0x100000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x200000 };
                                }
                            }
                        } else {
                            if (n > 17) {
                                if (n == 18) {
                                    return u256 { high: 0x0, low: 0x40000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x80000 };
                                }
                            } else {
                                if (n == 16) {
                                    return u256 { high: 0x0, low: 0x10000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x20000 };
                                }
                            }
                        }
                    }
                } else {
                    if (n > 7) {
                        if (n > 11) {
                            if (n > 13) {
                                if (n == 14) {
                                    return u256 { high: 0x0, low: 0x4000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x8000 };
                                }
                            } else {
                                if (n == 12) {
                                    return u256 { high: 0x0, low: 0x1000 };
                                } else {
                                    return u256 { high: 0x0, low: 0x2000 };
                                }
                            }
                        } else {
                            if (n > 9) {
                                if (n == 10) {
                                    return u256 { high: 0x0, low: 0x400 };
                                } else {
                                    return u256 { high: 0x0, low: 0x800 };
                                }
                            } else {
                                if (n == 8) {
                                    return u256 { high: 0x0, low: 0x100 };
                                } else {
                                    return u256 { high: 0x0, low: 0x200 };
                                }
                            }
                        }
                    } else {
                        if (n > 3) {
                            if (n > 5) {
                                if (n == 6) {
                                    return u256 { high: 0x0, low: 0x40 };
                                } else {
                                    return u256 { high: 0x0, low: 0x80 };
                                }
                            } else {
                                if (n == 4) {
                                    return u256 { high: 0x0, low: 0x10 };
                                } else {
                                    return u256 { high: 0x0, low: 0x20 };
                                }
                            }
                        } else {
                            if (n > 1) {
                                if (n == 2) {
                                    return u256 { high: 0x0, low: 0x4 };
                                } else {
                                    return u256 { high: 0x0, low: 0x8 };
                                }
                            } else {
                                if (n == 0) {
                                    return u256 { high: 0x0, low: 0x1 };
                                } else {
                                    return u256 { high: 0x0, low: 0x2 };
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
